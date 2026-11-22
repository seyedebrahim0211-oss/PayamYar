import 'dart:async' show Timer, unawaited;
import 'dart:convert' show jsonDecode, jsonEncode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../jalali.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_store.dart';
import '../group_sim_choice.dart';
import '../security/vault.dart';
import '../text_polish.dart';
import '../sms_bridge.dart';
import '../sms_groups.dart';
import '../recipient_suggestions.dart';
import 'compose_tools.dart';
import 'contact_picker.dart';
import 'share_contact_sms.dart';
import 'conversation_screen.dart';
import 'send_control.dart';
import 'bulk_queue_notice.dart';

/// SMS composition with an internal phone book and explicit multi-send confirmation.
class ComposeScreen extends StatefulWidget {
  final AppStore store;
  final String? initialTo;
  final String? initialBody;
  final List<String>? initialRecipients;
  final String? initialGroupName;
  final String? initialGroupId;
  final bool createGroup;
  /// Sending from a saved group must use exactly its current membership.
  final bool lockGroupRecipients;
  const ComposeScreen({super.key, required this.store, this.initialTo, this.initialBody,
    this.initialRecipients, this.initialGroupName, this.initialGroupId,
    this.createGroup = false, this.lockGroupRecipients = false});
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
  int? _explicitGroupSim;
  final Set<String> recipients = {};
  final Map<String, String> contactNames = {};
  List<Map<String, String>> _contacts = const [];
  Map<String, int> _frequency = const {};
  List<Map<String, String>> _suggestions = const [];
  Timer? _draftTimer;
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
    groupMode = widget.createGroup || widget.lockGroupRecipients;
    groupName.text = widget.initialGroupName ?? '';
    _restore();
    _loadSuggestions();
    if (store.android) _reloadSims();
  }

  Future<void> _restore() async {
    final hasInitial = widget.initialTo != null || widget.initialBody != null ||
        widget.initialRecipients != null || widget.createGroup;
    final draft = hasInitial ? null : await _readDraft();
    if (!mounted) return;
    setState(() {
      to.text = hasInitial ? widget.initialTo ?? '' : draft?.to ?? '';
      body.text = hasInitial ? widget.initialBody ?? '' : draft?.body ?? '';
      if (!hasInitial) recipients.addAll(draft?.recipients ?? const <String>[]);
      if (widget.initialRecipients != null) recipients.addAll(widget.initialRecipients!);
    });
  }

  // Drafts contain message text and phone numbers, so they are kept in the
  // Keystore-backed Vault instead of plain SharedPreferences.
  static const _draftToKey = 'draft_to';
  static const _draftBodyKey = 'draft_body';
  static const _draftRecipientsKey = 'draft_recipients';

  static Future<({String to, String body, List<String> recipients})> _readDraft() async {
    // One-time migration from older builds that stored drafts in plain prefs.
    final prefs = await SharedPreferences.getInstance();
    final legacyTo = prefs.getString(_draftToKey);
    final legacyBody = prefs.getString(_draftBodyKey);
    final legacyRecipients = prefs.getStringList(_draftRecipientsKey);
    if (legacyTo != null || legacyBody != null || legacyRecipients != null) {
      final legacy = (to: legacyTo ?? '', body: legacyBody ?? '',
        recipients: legacyRecipients ?? const <String>[]);
      try {
        await _writeDraft(legacy.to, legacy.body, legacy.recipients);
      } catch (_) {
        // Vault unavailable: keep the plain copy so the draft is not lost.
        return legacy;
      }
      await prefs.remove(_draftToKey);
      await prefs.remove(_draftBodyKey);
      await prefs.remove(_draftRecipientsKey);
      return legacy;
    }
    try {
      final rawRecipients = await Vault.get(_draftRecipientsKey);
      final decoded = rawRecipients == null || rawRecipients.isEmpty ? null : jsonDecode(rawRecipients);
      return (
        to: await Vault.get(_draftToKey) ?? '',
        body: await Vault.get(_draftBodyKey) ?? '',
        recipients: decoded is List ? decoded.map((e) => e.toString()).toList() : const <String>[],
      );
    } catch (_) {
      return (to: '', body: '', recipients: const <String>[]);
    }
  }

  static Future<void> _writeDraft(String number, String message, List<String> selected) async {
    // Empty fields are removed rather than stored.
    Future<void> save(String key, String value) =>
        value.isEmpty ? Vault.remove(key) : Vault.put(key, value);
    await save(_draftToKey, number);
    await save(_draftBodyKey, message);
    await save(_draftRecipientsKey, selected.isEmpty ? '' : jsonEncode(selected));
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
        _refreshSuggestions();
      });
    } catch (_) { /* Manual number entry remains available. */ }
  }

  void _chooseSuggestion(Map<String, String> item) {
    final number = RecipientSuggestions.key(item['number'] ?? '');
    if (recipients.length >= maxRecipients || !_isNumber(number)) return;
    setState(() {
      recipients.add(number);
      to.clear();
      _refreshSuggestions();
    });
    _saveDraft();
  }

  /// Delay writes during typing. Sending and recipient changes can still
  /// flush immediately; no SMS content leaves the device.
  void _refreshSuggestions() {
    _suggestions = _contacts.isEmpty ? const [] : RecipientSuggestions.rank(
      _contacts, _frequency, to.text,
      excluded: recipients.map(RecipientSuggestions.key).toSet(),
      limit: to.text.trim().isEmpty ? 4 : 5);
  }

  Future<void> _saveDraft({bool immediate = false}) async {
    _draftTimer?.cancel();
    if (immediate) {
      await _flushDraft();
    } else {
      _draftTimer = Timer(const Duration(milliseconds: 350), () =>
        unawaited(_flushDraft()));
    }
  }

  Future<void> _flushDraft() async {
    final number = to.text;
    final message = body.text;
    final selected = recipients.toList(growable: false);
    try {
      await _writeDraft(number, message, selected);
    } catch (_) {
      // Never fall back to plain storage for message drafts.
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    unawaited(_flushDraft());
    to.dispose();
    body.dispose();
    groupName.dispose();
    super.dispose();
  }

  // Canonical form (0912…), so +98912… and 0912… are one recipient, not two SMS.
  // Invalid input is returned as typed so validation can still report it.
  String _normalize(String number) {
    final plain = SmsBridge.normalizeNumber(number).replaceAll(RegExp(r'[\s()\-]'), '');
    return _isNumber(plain) ? RecipientSuggestions.key(plain) : plain;
  }
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
      _refreshSuggestions();
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
      FocusManager.instance.primaryFocus?.unfocus();
      final valid = contacts.where((c) => _isNumber(_normalize(c['number'] ?? '')))
          .map((c) => <String, String>{'name': c['name'] ?? '', 'number': _normalize(c['number'] ?? '')})
          .toList();
      setState(() {
        _contacts = valid;
        _frequency = RecipientSuggestions.frequency(store.messages);
        contactNames.addAll({for (final c in valid) c['number']!: c['name']!});
        _refreshSuggestions();
      });
      final selected = await showContactPicker(context,
        frequency: _frequency,
        contacts: valid,
        selected: {...recipients}, maxSelection: maxRecipients);
      if (selected == null || !mounted) return;
      setState(() {
        recipients
          ..clear()
          ..addAll(selected.map(_normalize));
        _refreshSuggestions();
      });
      await _saveDraft(immediate: true);
    } catch (_) {
      store.onNotice?.call('خواندن مخاطبان ممکن نشد. مجوز دفترچه تلفن را بررسی کنید.');
    } finally {
      if (mounted) setState(() => openingContacts = false);
    }
  }

  List<String>? _targets() {
    if (widget.lockGroupRecipients) {
      for (final group in store.smsGroups.groups) {
        if (group.id == widget.initialGroupId) {
          return List<String>.of(group.recipients);
        }
      }
      store.onNotice?.call('این گروه حذف شده است؛ ارسال انجام نشد.');
      return null;
    }
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
    if (widget.lockGroupRecipients) {
      for (final group in store.smsGroups.groups) {
        if (group.id == widget.initialGroupId) return group;
      }
      store.onNotice?.call('گروه دیگر وجود ندارد؛ هیچ پیامکی ارسال نشد.');
      return null;
    }
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

  Future<void> _reloadSims() async {
    try {
      final discovered = await SmsBridge.subscriptions();
      if (!mounted) return;
      setState(() {
        store.sims = discovered.where((sim) =>
            sim['id'] is int && (sim['id'] as int) >= 0).toList();
        if (!store.sims.any((sim) => sim['id'] == _explicitGroupSim)) {
          _explicitGroupSim = null;
        }
      });
      if (store.sims.length == 1 && store.selectedSim != store.sims.first['id']) {
        store.selectSim(store.sims.first['id'] as int);
      }
    } catch (_) {
      // The user can try again. Never silently fall back to the default SIM.
    }
  }

  Future<int?> _groupSim() async {
    if (_explicitGroupSim == null) {
      store.onNotice?.call('برای ارسال گروهی، سیم‌کارت را در بخش «سیم‌کارت ارسال گروهی» انتخاب کنید.');
      return null;
    }
    try {
      final active = await SmsBridge.subscriptions();
      final selected = GroupSimChoice.active(_explicitGroupSim, active);
      if (selected == null) {
        store.onNotice?.call('سیم‌کارت انتخاب‌شده دیگر فعال نیست؛ دوباره انتخاب کنید.');
        if (mounted) setState(() => _explicitGroupSim = null);
        return null;
      }
      return await SmsBridge.resolveSendSim(selected);
    } on PlatformException catch (e) {
      store.onNotice?.call(e.message ?? 'بررسی سیم‌کارت انتخاب‌شده انجام نشد.');
      return null;
    } catch (_) {
      store.onNotice?.call('سیم‌کارت انتخاب‌شده قابل استفاده نیست.');
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
    // A broadcast always needs an explicit choice; Android's default-SIM
    // fallback is unsuitable for multi-recipient messages.
    int? groupSim;
    if ((targets.length > 1 || groupMode) && store.android) {
      if (!store.permissions.isDefault || !store.permissions.canSend) {
        store.onNotice?.call('برای ارسال گروهی، پیام‌یار را پیام‌رسان پیش‌فرض کنید و مجوز ارسال را بدهید.');
        return;
      }
      groupSim = await _groupSim();
      if (!mounted || groupSim == null) return;
    }
    if (targets.length > 1) {
      final undoNote = store.settings?.sendDelayEnabled == false
          ? 'ارسال فوری است و امکان لغو بعد از ثبت محدود است.'
          : 'مهلت لغو هر پیام ${Jalali.digits(store.settings?.sendDelaySeconds ?? 5)} ثانیه است.';
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
        AlertDialog(
          title: Text(groupMode ? 'تأیید ارسال به گروه' : 'تأیید ارسال جداگانه'),
          content: Text('متن پیام به ${targets.length} شماره، به‌صورت پیامک جداگانه ارسال می‌شود. '
            'اپراتور ممکن است برای هر پیامک هزینه دریافت کند. '
            'سیم‌کارت انتخابی: ${store.sims.where((sim) => sim['id'] == groupSim).map((sim) => sim['label']).firstOrNull ?? 'انتخاب‌شده'}. '
            'پس از تأیید، پیام‌ها در صف کنترل‌شده (حداکثر ۱۲ تلاش در دقیقه و فاصله دست‌کم ۴ ثانیه) ثبت می‌شوند. '
            'پس از تأیید ارسال شبکه، نوبت مخاطب بعدی می‌رسد؛ در خطای شبکه صف متوقف می‌شود. '
            'این روش تضمین عبور از محدودیت اپراتور نیست؛ $undoNote'),
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
      final pending = await store.send(number, text, groupSim: groupSim, groupTime: savedGroup == null ? null : queuedAt);
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
          store.settings?.withSignature(text) ?? text, acceptedAt, exactTime: true);
      } catch (_) {
        store.onNotice?.call('ثبت سابقه ارسال گروه در حافظه امن ممکن نشد؛ پیام‌های صف‌شده حذف نشده‌اند.');
      }
    }
    if (!mounted) return;
    if (stopQueueing) {
      // Numbers whose undo window already ran out are still going to receive the SMS;
      // restoring them too would make a second tap on Send message them twice.
      final stillGoing = {
        for (final p in undoGroup) if (store.pendingSends.contains(p)) store.key(p.to)
      };
      setState(() {
        sending = false;
        recipients
          ..clear()
          ..addAll(targets.where((t) => !stillGoing.contains(store.key(t))));
        body.text = text;
      });
      await _saveDraft(immediate: true);
      return;
    }
    setState(() { sending = false; });
    if (targets.length == 1 && failed.isEmpty) {
      final address = targets.single;
      to.clear();
      body.clear();
      recipients.clear();
      await _saveDraft(immediate: true);
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
    await _saveDraft(immediate: true);
    if (!mounted) return;
    if (failed.isNotEmpty) {
      store.onNotice?.call('${failed.length} شماره در صف قرار نگرفت؛ متن برای ارسال مجدد محفوظ است.');
    }
  }

  void _showLocalStickers() {
    // Unicode motifs travel as normal SMS. Image stickers require MMS/RCS and
    // are deliberately not misrepresented as supported by ordinary SMS.
    const stickers = ['🌹', '💐', '🇮🇷', '🌙', '🕌', '🤲', '📿', '✨',
      '🎉', '🎂', '🕊️', '🌺', '❤️', '🌷', '🙏', '😊', '😄', '💚',
      '🌄', '🏜️', '☀️', '🍉', '🧿', '🎨'];
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('نمادها و استیکرهای متنی ایرانی',
            style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('با پیامک معمولی منتقل می‌شوند؛ تصویر یا استیکر متحرک نیستند.'),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final symbol in stickers)
              ActionChip(label: Text(symbol, style: const TextStyle(fontSize: 24)),
                onPressed: () {
                  setState(() => body.text += symbol);
                  _saveDraft();
                  Navigator.pop(ctx);
                }),
          ]),
        ]),
      )));
  }

  Future<void> _shortenSms() async {
    final original = body.text;
    final compact = TextPolish.compactSms(original);
    if (compact == original) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('فاصله اضافی قابل حذف در این متن پیدا نشد.')));
      return;
    }
    final before = TextPolish.smsParts(original);
    final after = TextPolish.smsParts(compact);
    final apply = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('بهینه‌سازی تعداد پیامک'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('قبل: ${before.parts} بخش • ${original.length} نویسه'),
          Text('بعد: ${after.parts} بخش • ${compact.length} نویسه',
            style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('پیش‌نمایش متن؛ هیچ واژه‌ای حذف نمی‌شود و پیام بدون تأیید شما ارسال نخواهد شد.'),
          const SizedBox(height: 8),
          SelectableText(compact),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('بدون تغییر')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('جایگزینی متن')),
      ],
    ));
    if (apply != true || !mounted) return;
    setState(() => body.text = compact);
    await _saveDraft(immediate: true);
  }

  Future<void> _pickOccasion() async {
    final now = DateTime.now();
    final choices = <String>[];
    String title = 'در هفت روز آینده مناسبتی ثبت نشده است';
    for (var offset = 0; offset <= 7; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset, 12);
      final date = Jalali.fromGregorian(day.year, day.month, day.day);
      final name = switch ((date[1], date[2])) {
        (1, 1) => 'نوروز', (9, 30) => 'شب یلدا', _ => null,
      };
      if (name == null) continue;
      title = offset == 0 ? 'امروز · $name' : '$name · ${Jalali.digits(offset)} روز دیگر';
      final prefix = offset == 0 ? '' : 'پیشاپیش ';
      choices.addAll(['$prefix$name مبارک! امیدوارم بهت خوش بگذره.',
        '$prefixفرارسیدن $name را به شما تبریک می‌گویم.',
        'عزیزانم، $prefix$name مبارک! به امید دیدار.']);
      break;
    }
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final favorites = preferences.getStringList('occasionFavorites') ?? <String>[];
    final draft = body.text.trim();
    final selected = await showModalBottomSheet<String>(context: context,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(title)),
        for (final (index, text) in choices.indexed) ListTile(
          subtitle: Text(const ['دوستانه', 'رسمی', 'خانوادگی'][index]),
          title: Text(text), onTap: () => Navigator.pop(sheet, text)),
        if (draft.isNotEmpty && !favorites.contains(draft)) ListTile(
          leading: const Icon(Icons.bookmark_add_outlined), title: const Text('ذخیره متن فعلی در علاقه‌مندی‌ها'),
          onTap: () async {
            await preferences.setStringList('occasionFavorites', {...favorites, draft}.toList());
            if (sheet.mounted) Navigator.pop(sheet);
          }),
        if (favorites.isNotEmpty) const ListTile(title: Text('علاقه‌مندی‌ها')),
        for (final favorite in favorites) ListTile(title: Text(favorite),
          onTap: () => Navigator.pop(sheet, favorite)),
      ])));
    if (!mounted || selected == null) return;
    final value = body.text.isEmpty ? selected : '${body.text} $selected';
    body.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _targetsPreviewCount();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        actions: [Padding(padding: const EdgeInsetsDirectional.only(end: 12),
          child: Center(child: Text('$count از $maxRecipients', style: Theme.of(context).textTheme.labelMedium)))],
        title: Text(widget.lockGroupRecipients ? 'ارسال به گروه: ${groupName.text}' : 'پیام جدید'),
      ),
      body: Column(children: [
        Expanded(child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          if (widget.lockGroupRecipients)
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: Text(groupName.text),
                subtitle: Text('گیرندگان این ارسال فقط اعضای ذخیره‌شده گروه هستند؛ '
                  'برای افزودن یا حذف مخاطب از بخش مدیریت گروه استفاده کنید.'),
              ),
            )
          else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: TextField(
                  controller: to,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.start,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTyped(),
                  onChanged: (_) { _refreshSuggestions(); _saveDraft(); setState(() {}); },
                  decoration: const InputDecoration(
                    hintText: 'نام یا شماره گیرنده',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    border: InputBorder.none,
                    filled: false,
                  ),
                )),
                if (to.text.trim().isNotEmpty && _isNumber(_normalize(to.text.trim())))
                  IconButton(
                    tooltip: 'افزودن شماره',
                    onPressed: _addTyped,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                IconButton.filledTonal(
                  tooltip: 'انتخاب از مخاطبان',
                  onPressed: openingContacts ? null : _openContacts,
                  icon: const Icon(Icons.contacts_outlined),
                ),
              ]),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(to.text.trim().isEmpty ? 'مخاطبین پرکاربرد' : 'پیشنهاد بر اساس نام و شماره',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary)),
                if (to.text.trim().isNotEmpty)
                  for (final item in _suggestions)
                    ListTile(
                      dense: true, visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: Text(item['name']?.isNotEmpty == true ? item['name']! : item['number']!),
                      subtitle: Text(item['number'] ?? '', textDirection: TextDirection.ltr),
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => _chooseSuggestion(item)),
                if (to.text.trim().isEmpty && _suggestions.isNotEmpty)
                  // Height follows the text scale so chip labels are not clipped.
                  SizedBox(height: MediaQuery.textScalerOf(context).scale(40), child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final item in _suggestions)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.person_add_alt_rounded, size: 16),
                            label: Text(item['name']?.isNotEmpty == true ? item['name']! : item['number']!),
                            onPressed: () => _chooseSuggestion(item)),
                        ),
                    ],
                  )),
              ],
              if (recipients.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final number in recipients.take(8))
                    InputChip(
                      label: Text(contactNames[number] ?? number,
                        textDirection: TextDirection.rtl),
                      tooltip: number,
                      onDeleted: () {
                        setState(() { recipients.remove(number); _refreshSuggestions(); });
                        _saveDraft();
                      },
                    ),
                  if (recipients.length > 8)
                    Chip(label: Text('و ${recipients.length - 8} نفر دیگر…')),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 18),

          TextField(
            controller: body,
            onChanged: (_) { _saveDraft(); setState(() {}); },
            maxLength: 2000,
            minLines: 4,
            // Grow with the text so the page scrolls; an inner scrollable field made the
            // page stick when the finger landed on it.
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              labelText: 'متن پیام',
              hintText: 'پیام خود را بنویسید…',
              alignLabelWithHint: true,
              counterText: '',
              contentPadding: EdgeInsets.all(18),
            ),
          ),
          if (!widget.lockGroupRecipients && (count > 1 || groupMode)) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('ارسال یک متن به چند مخاطب', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.person_outline_rounded),
                        label: Text('چند مخاطب')),
                      ButtonSegment(value: true, icon: Icon(Icons.groups_rounded),
                        label: Text('گروه پیامکی')),
                    ],
                    selected: {groupMode},
                    onSelectionChanged: sending ? null : (v) => setState(() => groupMode = v.first),
                  ),
                  const SizedBox(height: 8),
                  const Text('هر مخاطب یک پیامک جداگانه دریافت می‌کند؛ ارسال‌ها '
                    'به ترتیب انجام می‌شوند. هزینه هر پیام بر اساس تعرفه سیم‌کارت است.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
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
          if (store.android && (count > 1 || groupMode)) ...[
            const SizedBox(height: 12),
            Card(
              color: scheme.primaryContainer.withValues(alpha: .45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.sim_card_rounded, color: scheme.primary),
                    const SizedBox(width: 9),
                    Expanded(child: Text('سیم‌کارت ارسال گروهی',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800))),
                    IconButton(
                      tooltip: 'بازخوانی سیم‌کارت‌ها',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: sending ? null : _reloadSims),
                  ]),
                  const SizedBox(height: 6),
                  Text('قبل از تأیید ارسال، سیم‌کارتی را انتخاب کنید که هزینه پیامک‌ها از آن محاسبه شود.',
                    style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  if (!store.sims.any((sim) => sim['id'] is int && (sim['id'] as int) >= 0)) ...[
                    const Text('سیم‌کارتی قابل انتخاب نیست. اگر سیم‌کارت فعال دارید، دسترسی «تلفن» را در تنظیمات اندروید برای پیام‌یار فعال کنید.'),
                    const SizedBox(height: 5),
                    Align(alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: sending ? null : SmsBridge.openAppSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('تنظیمات دسترسی گوشی'))),
                  ] else Wrap(spacing: 8, runSpacing: 7, children: [
                    for (final sim in store.sims)
                      if (sim['id'] is int && (sim['id'] as int) >= 0)
                        ChoiceChip(
                          avatar: Icon(_explicitGroupSim == sim['id']
                              ? Icons.check_circle_rounded : Icons.sim_card_outlined,
                            size: 18),
                          label: Text(sim['label']?.toString() ?? 'سیم‌کارت'),
                          selected: _explicitGroupSim == sim['id'],
                          onSelected: sending ? null : (_) =>
                            setState(() => _explicitGroupSim = sim['id'] as int)),
                  ]),
                  if (_explicitGroupSim == null) ...[
                    const SizedBox(height: 5),
                    Text('انتخاب سیم‌کارت برای ارسال به چند گیرنده اجباری است.',
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                  ],
                ]),
              ),
            ),
          ],
          if (store.android && count <= 1 && !groupMode) ...[
            const SizedBox(height: 12),
            Card(
              key: const ValueKey('compose-sim-choice'),
              color: scheme.primaryContainer.withValues(alpha: .35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.sim_card_outlined, color: scheme.primary),
                    const SizedBox(width: 9),
                    Expanded(child: Text('سیم‌کارت ارسال',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                    IconButton(
                      tooltip: 'بازخوانی سیم‌کارت‌ها',
                      onPressed: sending ? null : _reloadSims,
                      icon: const Icon(Icons.refresh_rounded)),
                  ]),
                  if (store.sims.isEmpty)
                    const Text('سیم‌کارت شناسایی نشد؛ دسترسی تلفن را فعال کنید و بازخوانی بزنید.')
                  else
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final sim in store.sims)
                        ChoiceChip(
                          label: Text(sim['label']?.toString() ?? 'سیم‌کارت'),
                          avatar: Icon(store.selectedSim == sim['id']
                            ? Icons.check_circle_rounded : Icons.sim_card_rounded, size: 18),
                          selected: store.selectedSim == sim['id'],
                          onSelected: sending ? null : (_) =>
                            setState(() => store.selectSim(sim['id'] as int)),
                        ),
                    ]),
                  if (store.sims.isNotEmpty &&
                      !store.sims.any((sim) => sim['id'] == store.selectedSim))
                    Text('برای ارسال، سیم‌کارت ۱ یا ۲ را انتخاب کنید.',
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                ]),
              ),
            ),
          ],
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
            Text('${Jalali.digits(body.text.length)}/۲۰۰۰', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              key: const ValueKey('compose-templates'),
              initiallyExpanded: false,
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('پیام‌های آماده و مناسبتی'),
              children: [
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('پیشنهاد پیام مناسبتی'),
                  onTap: _pickOccasion),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final suggestion in quickTexts)
                      ActionChip(label: Text(suggestion), onPressed: () {
                        setState(() => body.text = suggestion);
                        _saveDraft();
                      }),
                  ]),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final result = await showTemplatesSheet(context, store, currentText: body.text);
                    if (result == null || !mounted) return;
                    setState(() => body.text = result);
                    _saveDraft();
                  },
                  icon: const Icon(Icons.library_books_outlined, size: 18),
                  label: const Text('مشاهده همه متن‌های آماده'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              initiallyExpanded: false,
              dense: true,
              leading: const Icon(Icons.tune_rounded),
              title: const Text('ابزارهای بیشتر'),
              subtitle: const Text('استیکر، اصلاح متن و کاهش بخش‌های پیامک'),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  label: const Text('استیکرهای متنی و نمادهای ایرانی'),
                  onPressed: _showLocalStickers),
                const SizedBox(height: 5),
                OutlinedButton.icon(
                  icon: const Icon(Icons.compress_rounded),
                  label: const Text('کاهش تعداد بخش‌های پیامک • با پیش‌نمایش'),
                  onPressed: body.text.trim().isEmpty ? null : _shortenSms),
                const SizedBox(height: 5),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('ویرایش املا و لحن پیام'),
                  onPressed: body.text.trim().isEmpty ? null : () async {
                    final edited = await showPolishSheet(context, body.text);
                    if (edited == null || !mounted) return;
                    setState(() => body.text = edited);
                    _saveDraft();
                  }),
              ],
            ),
          ),
        ])),
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BulkQueueNotice(),
            Row(children: [
              SendControl(
                key: const ValueKey('compose-send-control'),
                requests: undoGroup,
                sending: sending,
                enabled: !sending,
                onSend: () => _send(),
                onUndo: () async {
                  var cancelled = 0;
                  final cancelledTo = <String>[];
                  stopQueueing = true;
                  for (final request in List<PendingSend>.of(undoGroup)) {
                    if (!request.deadline.isAfter(DateTime.now())) continue;
                    if (!store.pendingSends.contains(request)) continue;
                    if (await store.undo(request)) {
                      cancelled++;
                      cancelledTo.add(request.to);
                    }
                  }
                  if (!mounted) return;
                  setState(() {
                    // Put back exactly the recipients whose message was really cancelled.
                    for (final n in cancelledTo) {
                      if (!recipients.any((r) => store.key(r) == store.key(n))) recipients.add(n);
                    }
                    undoGroup.removeWhere((p) => !store.pendingSends.contains(p));
                    if (cancelled > 0 || sending) body.text = lastSentBody;
                  });
                  if (cancelled > 0 || stopQueueing) _saveDraft();
                },
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(sending
                  ? '${Jalali.digits(queuedCount)} از ${Jalali.digits(count)} ثبت در صف کنترل‌شده'
                  : count > 1 ? 'ارسال جداگانه به ${Jalali.digits(count)} مخاطب' : 'ارسال پیامک',
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
    if (widget.lockGroupRecipients) {
      for (final group in store.smsGroups.groups) {
        if (group.id == widget.initialGroupId) return group.recipients.length;
      }
      return 0;
    }
    final numbers = <String>{...recipients};
    for (final number in to.text.split(RegExp(r'[,;\n،]+'))) {
      if (_normalize(number).isNotEmpty) numbers.add(_normalize(number.trim()));
    }
    return numbers.length;
  }
}
