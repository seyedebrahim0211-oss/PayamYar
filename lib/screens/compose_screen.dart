import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_store.dart';
import '../sms_bridge.dart';
import 'compose_tools.dart';
import 'contact_picker.dart';
import 'conversation_screen.dart';

/// SMS composition with an internal phone book and explicit multi-send confirmation.
class ComposeScreen extends StatefulWidget {
  final AppStore store;
  final String? initialTo;
  final String? initialBody;
  const ComposeScreen({super.key, required this.store, this.initialTo, this.initialBody});
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  static const maxRecipients = 50;
  static const quickTexts = <String>[
    'در جلسه هستم، بعداً تماس می‌گیرم.',
    'رسیدم.',
    'چند دقیقه دیگر می‌رسم.',
    'ممنون 🌹',
  ];
  final to = TextEditingController();
  final body = TextEditingController();
  final Set<String> recipients = {};
  final Map<String, String> contactNames = {};
  bool sending = false;
  bool openingContacts = false;
  int queuedCount = 0;
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final hasInitial = widget.initialTo != null || widget.initialBody != null;
    setState(() {
      to.text = hasInitial ? widget.initialTo ?? '' : prefs.getString('draft_to') ?? '';
      body.text = hasInitial ? widget.initialBody ?? '' : prefs.getString('draft_body') ?? '';
      if (!hasInitial) recipients.addAll(prefs.getStringList('draft_recipients') ?? []);
    });
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('draft_to', to.text);
    await prefs.setString('draft_body', body.text);
    await prefs.setStringList('draft_recipients', recipients.toList());
  }

  @override
  void dispose() {
    to.dispose();
    body.dispose();
    super.dispose();
  }

  String _normalize(String number) => SmsBridge.normalizeNumber(number)
      .replaceAll(RegExp(r'[\s()\-]'), '');
  bool _isNumber(String number) => RegExp(r'^\+?[0-9]{3,15}$').hasMatch(number);

  void _addTyped() {
    final values = to.text.split(RegExp(r'[,;\n،]+'))
        .map((s) => _normalize(s.trim())).where((s) => s.isNotEmpty);
    final incoming = values.toSet();
    if (incoming.isEmpty) return;
    if (incoming.any((number) => !_isNumber(number))) {
      store.onNotice?.call('یکی از شماره‌های واردشده معتبر نیست.');
      return;
    }
    if ({...recipients, ...incoming}.length > maxRecipients) {
      store.onNotice?.call('در هر نوبت حداکثر ۵۰ گیرنده انتخاب کنید.');
      return;
    }
    setState(() {
      recipients.addAll(incoming);
      to.clear();
    });
    _saveDraft();
  }

  Future<void> _openContacts() async {
    if (openingContacts || sending) return;
    setState(() => openingContacts = true);
    try {
      if (!store.permissions.contacts) {
        final updated = await store.requestPermissions();
        if (!updated.contacts) {
          store.onNotice?.call('برای انتخاب مخاطبان، مجوز دفترچه تلفن را در تنظیمات برنامه فعال کنید.');
          return;
        }
      }
      final contacts = await SmsBridge.listContacts();
      if (!mounted) return;
      for (final item in contacts) {
        final number = _normalize(item['number'] ?? '');
        if (_isNumber(number)) contactNames[number] = item['name'] ?? number;
      }
      final selected = await showContactPicker(context,
        contacts: contacts.where((c) => _isNumber(_normalize(c['number'] ?? ''))).toList(),
        selected: {...recipients}, maxSelection: maxRecipients);
      if (selected == null || !mounted) return;
      setState(() {
        recipients
          ..clear()
          ..addAll(selected.map(_normalize));
      });
      await _saveDraft();
    } catch (_) {
      store.onNotice?.call('خواندن مخاطبان ممکن نشد. مجوز دفترچه تلفن را بررسی کنید.');
    } finally {
      if (mounted) setState(() => openingContacts = false);
    }
  }

  List<String>? _targets() {
    final result = <String>{...recipients};
    for (final raw in to.text.split(RegExp(r'[,;\n،]+'))) {
      if (raw.trim().isEmpty) continue;
      final number = _normalize(raw.trim());
      if (!_isNumber(number)) {
        store.onNotice?.call('شماره «' + raw.trim() + '» معتبر نیست.');
        return null;
      }
      result.add(number);
    }
    if (result.length > maxRecipients) {
      store.onNotice?.call('برای جلوگیری از ارسال ناخواسته، حداکثر ۵۰ گیرنده مجاز است.');
      return null;
    }
    return result.toList(growable: false);
  }

  Future<void> _send() async {
    if (sending) return;
    final targets = _targets();
    if (targets == null) return;
    final text = body.text.trim();
    if (targets.isEmpty || text.isEmpty) {
      store.onNotice?.call('حداقل یک گیرنده و متن پیام را وارد کنید.');
      return;
    }
    if (targets.length > 1) {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
        AlertDialog(
          title: const Text('تأیید ارسال گروهی'),
          content: Text('متن پیام به ${targets.length} شماره، به‌صورت پیامک جداگانه ارسال می‌شود. '
            'اپراتور ممکن است برای هر پیامک هزینه دریافت کند. '
            'پس از تأیید، برای هر پیام ۵ ثانیه مهلت لغو وجود دارد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بازگشت')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید و ارسال')),
          ],
        ));
      if (confirmed != true || !mounted) return;
    }
    setState(() { sending = true; queuedCount = 0; });
    final failed = <String>[];
    PendingSend? lastPending;
    for (final number in targets) {
      final pending = await store.send(number, text);
      if (pending == null && store.android) {
        failed.add(number);
      } else {
        lastPending = pending;
        if (mounted) setState(() => queuedCount++);
      }
    }
    if (!mounted) return;
    setState(() => sending = false);
    if (targets.length == 1 && failed.isEmpty) {
      final address = targets.single;
      to.clear();
      body.clear();
      recipients.clear();
      await _saveDraft();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(store: store, address: address)));
      if (lastPending != null) {
        final undo = lastPending;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 5),
            content: const Text('پیام در صف ارسال است'),
            action: SnackBarAction(label: 'لغو', onPressed: () => store.undo(undo)),
          ));
      }
      return;
    }
    setState(() {
      recipients
        ..clear()
        ..addAll(failed);
      to.clear();
      if (failed.isEmpty) body.clear();
    });
    await _saveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${targets.length - failed.length} پیامک در صف ارسال قرار گرفت. '
          '${failed.isEmpty ? 'برای پیگیری وضعیت، گفتگوها را ببینید.' : '${failed.length} شماره ثبت نشد؛ متن برای تلاش مجدد محفوظ است.'}'),
        duration: const Duration(seconds: 6),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _targetsPreviewCount();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('پیام جدید'),
      ),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Row(children: [
            Icon(Icons.people_alt_outlined, color: scheme.primary),
            const SizedBox(width: 8),
            Text('گیرندگان', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('$count انتخاب‌شده', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: TextField(
                  controller: to,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTyped(),
                  onChanged: (_) { _saveDraft(); setState(() {}); },
                  decoration: const InputDecoration(
                    hintText: 'نام یا شماره گیرنده',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    border: InputBorder.none,
                    filled: false,
                  ),
                )),
                IconButton.filledTonal(
                  tooltip: 'افزودن شماره',
                  onPressed: _addTyped,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
              if (recipients.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final number in recipients)
                    InputChip(
                      label: Text(contactNames[number] ?? number,
                        textDirection: TextDirection.rtl),
                      tooltip: number,
                      onDeleted: () { setState(() => recipients.remove(number)); _saveDraft(); },
                    ),
                ]),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: openingContacts ? null : _openContacts,
                icon: openingContacts
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.contacts_rounded),
                label: const Text('انتخاب مخاطب • چندتایی • انتخاب همه'),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('متن پیام', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: body,
            onChanged: (_) { _saveDraft(); setState(() {}); },
            maxLength: 2000,
            minLines: 5,
            maxLines: 9,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'پیام خود را اینجا بنویسید…',
              alignLabelWithHint: true,
              counterText: '',
              contentPadding: EdgeInsets.all(18),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: SmsCounter(text: body.text)),
            Text('${body.text.length}/۲۰۰۰', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Text('پیام‌های آماده', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final result = await showTemplatesSheet(context, store, currentText: body.text);
                if (result == null || !mounted) return;
                setState(() => body.text = result);
                _saveDraft();
              },
              icon: const Icon(Icons.library_books_outlined, size: 18),
              label: const Text('مشاهده همه'),
            ),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final suggestion in quickTexts)
              ActionChip(label: Text(suggestion), onPressed: () {
                setState(() => body.text = suggestion);
                _saveDraft();
              }),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('ویرایش املا و لحن پیام'),
            onPressed: body.text.trim().isEmpty ? null : () async {
              final edited = await showPolishSheet(context, body.text);
              if (edited == null || !mounted) return;
              setState(() => body.text = edited);
              _saveDraft();
            },
          ),
          if (store.sims.length > 2) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: store.selectedSim,
              decoration: const InputDecoration(labelText: 'سیم‌کارت ارسال', prefixIcon: Icon(Icons.sim_card_outlined)),
              items: [for (final sim in store.sims)
                DropdownMenuItem<int>(value: sim['id'] as int, child: Text(sim['label'].toString()))],
              onChanged: sending ? null : (value) => setState(() => store.selectedSim = value ?? -1),
            ),
          ],
        ])),
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(
              onPressed: sending ? null : _send,
              icon: sending ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, textDirection: TextDirection.ltr),
              label: Text(sending ? '$queuedCount از $count در صف ارسال'
                : count > 1 ? 'ارسال به $count گیرنده' : 'ارسال پیامک'),
            ),
            const SizedBox(height: 6),
            Text('تا ۵ ثانیه پس از ثبت هر پیام، می‌توانید ارسال آن را لغو کنید.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ]),
        )),
      ]),
    );
  }

  int _targetsPreviewCount() {
    final numbers = <String>{...recipients};
    for (final number in to.text.split(RegExp(r'[,;\n،]+'))) {
      if (_normalize(number).isNotEmpty) numbers.add(_normalize(number.trim()));
    }
    return numbers.length;
  }
}
