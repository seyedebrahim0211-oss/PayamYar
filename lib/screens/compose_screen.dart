import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_store.dart';
import '../sms_bridge.dart';
import '../sms_groups.dart';
import '../recipient_suggestions.dart';
import 'compose_tools.dart';
import 'contact_picker.dart';
import 'share_contact_sms.dart';
import 'conversation_screen.dart';
import 'send_control.dart';

/// SMS composition with an internal phone book and explicit multi-send confirmation.
class ComposeScreen extends StatefulWidget {
  final AppStore store;
  final String? initialTo;
  final String? initialBody;
  final List<String>? initialRecipients;
  final String? initialGroupName;
  final String? initialGroupId;
  final bool createGroup;
  const ComposeScreen({super.key, required this.store, this.initialTo, this.initialBody,
    this.initialRecipients, this.initialGroupName, this.initialGroupId, this.createGroup = false});
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  int get maxRecipients => store.settings?.recipientCapacity ?? 500;
  static const quickTexts = <String>[
    'در جلسه هستم، بعداً تماس می‌گیرم.',
    'رسیدم.',
    'چند دقیقه دیگر می‌رسم.',
    'ممنون 🌹',
  ];
  final to = TextEditingController();
  final body = TextEditingController();
  final groupName = TextEditingController();
  bool groupMode = false;
  final Set<String> recipients = {};
  final Map<String, String> contactNames = {};
  List<Map<String, String>> _contacts = const [];
  Map<String, int> _frequency = const {};
  final List<PendingSend> undoGroup = [];
  String lastSentBody = '';
  bool sending = false;
  bool stopQueueing = false;
  bool openingContacts = false;
  int queuedCount = 0;
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    groupMode = widget.createGroup;
    groupName.text = widget.initialGroupName ?? '';
    _restore();
    _loadSuggestions();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final hasInitial = widget.initialTo != null || widget.initialBody != null ||
        widget.initialRecipients != null || widget.createGroup;
    setState(() {
      to.text = hasInitial ? widget.initialTo ?? '' : prefs.getString('draft_to') ?? '';
      body.text = hasInitial ? widget.initialBody ?? '' : prefs.getString('draft_body') ?? '';
      if (!hasInitial) recipients.addAll(prefs.getStringList('draft_recipients') ?? []);
      if (widget.initialRecipients != null) recipients.addAll(widget.initialRecipients!);
    });
  }

  Future<void> _loadSuggestions() async {
    if (!store.permissions.contacts) return;
    try {
      final contacts = await SmsBridge.listContacts();
      if (!mounted) return;
      final valid = contacts.where((c) =>
        _isNumber(_normalize(c['number'] ?? ''))).map((c) =>
          <String, String>{'name': c['name'] ?? '', 'number': RecipientSuggestions.key(c['number'] ?? '')}).toList();
      setState(() {
        _contacts = valid;
        _frequency = RecipientSuggestions.frequency(store.messages);
        contactNames.addAll({for (final c in valid) c['number']!: c['name']!});
      });
    } catch (_) { /* Manual number entry remains available. */ }
  }

  void _chooseSuggestion(Map<String, String> item) {
    final number = RecipientSuggestions.key(item['number'] ?? '');
    if (recipients.length >= maxRecipients || !_isNumber(number)) return;
    setState(() {
      recipients.add(number);
      to.clear();
    });
    _saveDraft();
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
    groupName.dispose();
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
      store.onNotice?.call('حداکثر $maxRecipients گیرنده برای انتخاب مجاز است.');
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
        frequency: RecipientSuggestions.frequency(store.messages),
        contacts: contacts.where((c) => _isNumber(_normalize(c['number'] ?? '')))
          .map((c) => <String,String>{'name': c['name'] ?? '', 'number': _normalize(c['number'] ?? '')}).toList(),
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
        store.onNotice?.call('شماره «${raw.trim()}» معتبر نیست.');
        return null;
      }
      result.add(number);
    }
    if (result.length > maxRecipients) {
      store.onNotice?.call('حداکثر $maxRecipients گیرنده برای انتخاب مجاز است.');
      return null;
    }
    return result.toList(growable: false);
  }

  Future<SmsGroup?> _saveGroup(List<String> targets) async {
    if (targets.length < 2) {
      store.onNotice?.call('برای ساخت گروه حداقل ۲ مخاطب انتخاب کنید.');
      return null;
    }
    try {
      final saved = await store.smsGroups.save(groupName.text, targets,
        id: widget.initialGroupId);
      store.onNotice?.call('گروه پیامکی ذخیره شد؛ پاسخ اعضا همچنان خصوصی است.');
      return saved;
    } on ArgumentError catch (e) {
      store.onNotice?.call(e.message?.toString() ?? 'نام یا مخاطبان گروه معتبر نیست.');
      return null;
    }
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
    if (targets.length > 500) {
      store.onNotice?.call('برای ارسال بیش از ۵۰۰ شماره از پنل پیامکی مجاز استفاده کنید. افزایش سقف انتخاب، محدودیت اپراتور را تغییر نمی‌دهد.');
      return;
    }
    if (!mounted) return;
    if (targets.length > 1) {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
        AlertDialog(
          title: Text(groupMode ? 'تأیید ارسال به گروه' : 'تأیید ارسال جداگانه'),
          content: Text('متن پیام به ${targets.length} شماره، به‌صورت پیامک جداگانه ارسال می‌شود. '
            'اپراتور ممکن است برای هر پیامک هزینه دریافت کند. '
            'پس از تأیید، هر پیام جداگانه به صف ارسال می‌رود. به محدودیت‌های اپراتور و هزینه احتمالی توجه کنید؛ تا ۵ ثانیه پس از ثبت هر پیام امکان لغو آن وجود دارد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بازگشت')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید و ارسال')),
          ],
        ));
      if (confirmed != true || !mounted) return;
    }
    // Never create a new group merely because the confirmation dialog opened.
    final savedGroup = groupMode ? await _saveGroup(targets) : null;
    if (groupMode && savedGroup == null) return;
    if (!mounted) return;
    final acceptedAt = <String, DateTime>{};
    setState(() {
      sending = true;
      stopQueueing = false;
      queuedCount = 0;
      lastSentBody = text;
      undoGroup.clear();
    });
    final failed = <String>[];
    var processed = 0;
    for (final number in targets) {
      if (stopQueueing) break;
      final queuedAt = DateTime.now();
      final pending = await store.send(number, text);
      processed++;
      if (stopQueueing && pending != null) {
        await store.undo(pending);
        break;
      }
      if (pending == null && store.android) {
        failed.add(number);
      } else {
        if (pending != null) {
          undoGroup.add(pending);
          acceptedAt[number] = queuedAt;
        }
        if (mounted) {
          queuedCount++;
          if (queuedCount == 1 || queuedCount % 10 == 0 || processed == targets.length) {
            setState(() {});
          }
        }
      }
    }
    // Log only messages actually accepted into the native queue.
    // The group's original text is encrypted in Android Keystore; delivery
    // status is reconciled against SMS rows, never fabricated as 'sent'.
    if (savedGroup != null && acceptedAt.isNotEmpty) {
      try {
        await store.smsGroups.recordBatch(savedGroup.id,
          store.settings?.withSignature(text) ?? text, acceptedAt);
      } catch (_) {
        store.onNotice?.call('ثبت سابقه ارسال گروه در حافظه امن ممکن نشد؛ پیام‌های صف‌شده حذف نشده‌اند.');
      }
    }
    if (!mounted) return;
    if (stopQueueing) {
      setState(() {
        sending = false;
        recipients
          ..clear()
          ..addAll(targets);
        body.text = text;
      });
      await _saveDraft();
      return;
    }
    setState(() { sending = false; });
    if (targets.length == 1 && failed.isEmpty) {
      final address = targets.single;
      to.clear();
      body.clear();
      recipients.clear();
      await _saveDraft();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(store: store, address: address)));
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
    if (failed.isNotEmpty) {
      store.onNotice?.call('${failed.length} شماره در صف قرار نگرفت؛ متن برای ارسال مجدد محفوظ است.');
    }
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
            Text('$count از $maxRecipients', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
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
              if (_contacts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(to.text.trim().isEmpty ? 'مخاطبین پرکاربرد' : 'پیشنهاد بر اساس نام و شماره',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary)),
                for (final item in RecipientSuggestions.rank(_contacts, _frequency, to.text,
                    excluded: recipients.map(RecipientSuggestions.key).toSet(), limit: 5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_alt_1_outlined),
                    title: Text(item['name']?.isNotEmpty == true ? item['name']! : item['number']!),
                    subtitle: Text(item['number'] ?? '', textDirection: TextDirection.ltr),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _chooseSuggestion(item),
                  ),
              ],
              if (recipients.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final number in recipients.take(8))
                    InputChip(
                      label: Text(contactNames[number] ?? number,
                        textDirection: TextDirection.rtl),
                      tooltip: number,
                      onDeleted: () { setState(() => recipients.remove(number)); _saveDraft(); },
                    ),
                  if (recipients.length > 8)
                    Chip(label: Text('و ${recipients.length - 8} نفر دیگر…')),
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
          if (count > 1 || groupMode) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('نوع ارسال', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.person_outline_rounded),
                        label: Text('جداگانه')),
                      ButtonSegment(value: true, icon: Icon(Icons.groups_rounded),
                        label: Text('گروه پیامکی')),
                    ],
                    selected: {groupMode},
                    onSelectionChanged: sending ? null : (v) => setState(() => groupMode = v.first),
                  ),
                  if (groupMode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: groupName,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'نام گروه',
                        hintText: 'مثلاً همکاران یا خانواده',
                        prefixIcon: Icon(Icons.edit_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const Text('برای هر عضو پیامک جدا ارسال می‌شود. پاسخ هر مخاطب فقط در گفتگوی خصوصی او دیده می‌شود.',
                      style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: sending ? null : () async {
                        final targets = _targets();
                        if (targets != null) await _saveGroup(targets);
                      },
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('ذخیره گروه بدون ارسال')),
                  ],
                ]),
              ),
            ),
          ],
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
          Align(alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                final card = await selectContactForSms(context);
                if (card == null || !mounted) return;
                setState(() => body.text = body.text.trim().isEmpty ? card : '${body.text}\n$card');
                _saveDraft();
              },
              icon: const Icon(Icons.contact_page_outlined),
              label: const Text('افزودن کارت مخاطب به متن پیام'),
            )),
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
            Row(children: [
              SendControl(
                key: const ValueKey('compose-send-control'),
                requests: undoGroup,
                sending: sending,
                enabled: !sending,
                onSend: () => _send(),
                onUndo: () async {
                  var cancelled = 0;
                  stopQueueing = true;
                  for (final request in List<PendingSend>.of(undoGroup)) {
                    if (!request.deadline.isAfter(DateTime.now())) continue;
                    if (!store.pendingSends.contains(request)) continue;
                    if (await store.undo(request)) cancelled++;
                  }
                  if (!mounted) return;
                  setState(() {
                    undoGroup.removeWhere((p) => !store.pendingSends.contains(p));
                    if (cancelled > 0 || sending) body.text = lastSentBody;
                  });
                  if (cancelled > 0 || stopQueueing) _saveDraft();
                },
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(sending
                  ? '$queuedCount از $count در صف'
                  : count > 1 ? 'ارسال جداگانه به $count مخاطب' : 'ارسال پیامک',
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text('حلقه دور فلش، مهلت لغو پیام را نشان می‌دهد. پاسخ مخاطبان در گفتگوی شخصی آن‌هاست.',
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
