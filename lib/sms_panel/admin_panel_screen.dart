import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../jalali.dart';
import '../security/app_lock.dart';
import '../security/vault.dart';
import '../sms_bridge.dart';
import '../sms_groups.dart';
import '../screens/contact_picker.dart';
import 'meli_payamak.dart';

/// Admin/creator-only access. The entry is hidden (7 taps on the version in Settings) and
/// protected by a separate admin PIN; the panel itself works only with the owner's
/// Meli Payamak credentials, which never leave the Keystore vault except to the web service.
class AdminAccess {
  static const _flag = 'adminMode';
  static const pinName = 'admin';

  static Future<bool> enabled() async {
    // A SharedPreferences boolean is UI state, not proof of administrator identity.
    // Never expose the panel shortcut before a verified service account and PIN exist.
    if ((await SharedPreferences.getInstance()).getBool(_flag) != true) return false;
    return await Vault.hasPin(pinName) &&
        (await Vault.get('mp_user') ?? '').isNotEmpty &&
        (await Vault.get('mp_pass') ?? '').isNotEmpty;
  }

  static Future<void> _setEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_flag, v);

  /// Provisioning requires a *working* Meli Payamak account before the admin PIN
  /// can be created. A new PIN by itself never grants access to a panel.
  static Future<Map<String, String>?> _verifyOwner(BuildContext context) async {
    final username = TextEditingController();
    final password = TextEditingController();
    final sender = TextEditingController(text: MeliPayamak.defaultLine);
    bool checking = false;
    String? error;
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, refresh) => AlertDialog(
            title: const Text('تأیید مالک پنل ملی پیامک'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('برای فعال‌سازی دسترسی مدیر ابتدا حساب وب‌سرویس را تأیید کنید. '
                    'بدون حساب معتبر، فقط ساختن رمز مدیر کافی نیست.'),
                const SizedBox(height: 12),
                TextField(controller: username, enabled: !checking,
                    decoration: const InputDecoration(labelText: 'نام کاربری پنل')),
                const SizedBox(height: 8),
                TextField(controller: password, enabled: !checking, obscureText: true,
                    enableSuggestions: false, autocorrect: false,
                    decoration: const InputDecoration(labelText: 'کلید وب‌سرویس')),
                const SizedBox(height: 8),
                TextField(controller: sender, enabled: !checking,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'شماره خط پیامکی')),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed: checking ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('انصراف')),
              FilledButton(
                onPressed: checking ? null : () async {
                  final u = username.text.trim(), p = password.text.trim();
                  final l = sender.text.replaceAll(RegExp(r'[^0-9]'), '');
                  if (u.isEmpty || p.isEmpty || l.isEmpty) {
                    refresh(() => error = 'اطلاعات حساب و شماره خط را کامل کنید.');
                    return;
                  }
                  refresh(() { checking = true; error = null; });
                  final client = MeliPayamak(u, p);
                  try {
                    await client.credit();
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop({'user': u, 'pass': p, 'line': l});
                    }
                  } on PanelException catch (e) {
                    if (dialogContext.mounted) refresh(() => error = e.message);
                  } finally {
                    client.close();
                    if (dialogContext.mounted) refresh(() => checking = false);
                  }
                },
                child: Text(checking ? 'در حال بررسی…' : 'تأیید حساب')),
            ],
          ),
        ),
      );
    } finally {
      username.dispose();
      password.dispose();
      sender.dispose();
    }
  }

  /// Authenticates the panel owner, then creates/verifies the local admin PIN.
  static Future<void> open(BuildContext context, {void Function(String)? onNotice}) async {
    final nav = Navigator.of(context);
    if (!await Vault.hasPin(pinName)) {
      if (!context.mounted) return;
      final credentials = await _verifyOwner(context);
      if (credentials == null || !context.mounted) return;
      final pin = await askNewPin(context, title: 'رمز مدیر پنل پیامکی', minLength: 6);
      if (pin == null) return;
      // Persist credentials encrypted by Android Keystore; never in settings or source code.
      await Vault.put('mp_user', credentials['user']!);
      await Vault.put('mp_pass', credentials['pass']!);
      await Vault.put('mp_line', credentials['line']!);
      await Vault.setPin(pinName, pin);
      await _setEnabled(true);
      onNotice?.call('حالت مدیر با تأیید حساب فعال شد.');
    } else {
      var ok = false;
      await nav.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => PinScreen(
          title: 'ورود مدیر',
          subtitle: 'رمز مدیر را وارد کنید',
          minLength: 6,
          onCancel: () => Navigator.pop(ctx),
          onSubmit: (pin) async {
            final r = await Vault.verifyPin(pinName, pin);
            if (!r.ok) return r.message;
            ok = true;
            if (ctx.mounted) Navigator.pop(ctx);
            return null;
          },
        ),
      ));
      if (!ok) return;
    }
    await nav.push(MaterialPageRoute<void>(builder: (_) => AdminPanelScreen(onNotice: onNotice)));
  }

  /// Removes credentials and the admin PIN; the entry disappears from Settings.
  static Future<void> reset() async {
    for (final k in ['mp_user', 'mp_pass', 'mp_line']) {
      await Vault.remove(k);
    }
    await Vault.remove(pinName);
    await _setEnabled(false);
  }
}

class AdminPanelScreen extends StatefulWidget {
  final void Function(String)? onNotice;
  const AdminPanelScreen({super.key, this.onNotice});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> with WidgetsBindingObserver {
  Timer? _inboxRefreshTimer;
  bool _appVisible = true;
  MeliPayamak? api;
  String user = '';
  String line = MeliPayamak.defaultLine;
  double? credit;
  String? error;
  bool loading = true;
  List<PanelMessage> inbox = const [];
  List<PanelMessage> sent = const [];
  int seenMax = 0;

  final userField = TextEditingController();
  final passField = TextEditingController();
  final lineField = TextEditingController(text: MeliPayamak.defaultLine);
  final toField = TextEditingController();
  final textField = TextEditingController();
  bool flash = false;
  bool sending = false;
  String? lastRecId;
  String? lastDelivery;
  TabController? _tabs;

  void _notice(String t) {
    widget.onNotice?.call(t);
    if (widget.onNotice == null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Only poll while this private panel is actually foregrounded.
    _inboxRefreshTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (mounted && _appVisible && api != null && !loading) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    // Panel balance is operational credit, not private banking report data.
  }

  @override
  void dispose() {
    _inboxRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    api?.close();
    for (final c in [userField, passField, lineField, toField, textField]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final u = await Vault.get('mp_user') ?? '';
    final p = await Vault.get('mp_pass') ?? '';
    final l = await Vault.get('mp_line') ?? MeliPayamak.defaultLine;
    seenMax = (await SharedPreferences.getInstance()).getInt('mp_seen_max') ?? 0;
    userField.text = u;
    lineField.text = l;
    setState(() {
      user = u;
      line = l;
      api = u.isEmpty || p.isEmpty ? null : MeliPayamak(u, p);
      loading = api != null;
    });
    if (api != null) await _refresh();
  }

  Future<void> _refresh() async {
    final a = api;
    if (a == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final c = await a.credit();
      final received = await a.messages(location: 1, count: 100);
      List<PanelMessage> out = const [];
      try {
        out = await a.messages(location: 2, count: 50);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        credit = c;
        // Messages sent to this line (e.g. 90008325); keep all when the service omits the receiver.
        inbox = received.where((m) {
          final receiver = m.receiver.replaceAll(RegExp(r'[^0-9]'), '');
          final wanted = line.replaceAll(RegExp(r'[^0-9]'), '');
          return receiver.isEmpty || receiver == wanted;
        }).toList();
        sent = out;
      });
    } on PanelException catch (e) {
      if (mounted) { setState(() {
        error = e.message;
        credit = null;
        inbox = const [];
        sent = const [];
      }); }
    } finally {
      if (mounted) { setState(() => loading = false); }
    }
  }

  int get unread => inbox.where((m) => m.id > seenMax).length;

  Future<void> _markSeen() async {
    if (inbox.isEmpty) return;
    final max = inbox.map((m) => m.id).reduce((a, b) => a > b ? a : b);
    if (max <= seenMax) return;
    seenMax = max;
    await (await SharedPreferences.getInstance()).setInt('mp_seen_max', max);
    if (mounted) setState(() {});
  }

  Future<void> _saveCredentials() async {
    final u = userField.text.trim();
    final p = passField.text.trim();
    final l = lineField.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (u.isEmpty || (p.isEmpty && api == null) || l.isEmpty) {
      _notice('نام کاربری، کلید وب‌سرویس و شماره خط را کامل کنید.');
      return;
    }
    final pass = p.isEmpty ? (await Vault.get('mp_pass') ?? '') : p;
    final test = MeliPayamak(u, pass);
    setState(() => loading = true);
    try {
      final c = await test.credit();
      await Vault.put('mp_user', u);
      await Vault.put('mp_pass', pass);
      await Vault.put('mp_line', l);
      passField.clear();
      api?.close();
      setState(() {
        api = test;
        user = u;
        line = l;
        credit = c;
        error = null;
      });
      _notice('اتصال به ملی پیامک برقرار شد.');
      await _refresh();
    } on PanelException catch (e) {
      test.close();
      _notice(e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  int _parts(String t) {
    final unicode = t.runes.any((r) => r > 127);
    final single = unicode ? 70 : 160, multi = unicode ? 67 : 153;
    if (t.isEmpty) return 0;
    return t.length <= single ? 1 : (t.length / multi).ceil();
  }

  Future<void> _send() async {
    final a = api;
    if (a == null) return;
    final numbers = toField.text.split(RegExp(r'[\s,،;]+')).map(MeliPayamak.normalize).where((n) => n.isNotEmpty).toSet().toList();
    final text = textField.text.trim();
    if (numbers.isEmpty || text.isEmpty) {
      _notice('گیرنده معتبر و متن پیام را وارد کنید.');
      return;
    }
    final parts = _parts(text) * numbers.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ارسال از پنل ملی پیامک'),
        content: Text('از خط ${Jalali.digits(line)} به ${Jalali.digits(numbers.length)} گیرنده ارسال شود؟\n'
            'هزینه تقریبی: ${Jalali.digits(parts)} پیامک از اعتبار پنل.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ارسال')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => sending = true);
    try {
      final id = await a.send(to: numbers, text: text, from: line, flash: flash);
      setState(() {
        lastRecId = id;
        lastDelivery = null;
      });
      textField.clear();
      _notice('ارسال شد. شناسه: $id');
      try {
        credit = await a.credit();
      } catch (_) {}
    } on PanelException catch (e) {
      _notice(e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _checkDelivery() async {
    final a = api, id = lastRecId;
    if (a == null || id == null) return;
    try {
      final code = await a.delivery(id);
      setState(() => lastDelivery = MeliPayamak.deliveryText(code));
    } on PanelException catch (e) {
      _notice(e.message);
    }
  }

  Future<void> _openUrl(String url) async {
    if (!Platform.isAndroid) return;
    final ok = await const MethodChannel('ir.honarmardomi.payamyar/sms').invokeMethod<bool>('openUrl', {'url': url});
    if (ok != true) {
      await Clipboard.setData(ClipboardData(text: url));
      _notice('نشانی کپی شد: $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پنل ملی پیامک'),
          actions: [
            IconButton(tooltip: 'به‌روزرسانی', onPressed: loading ? null : _refresh, icon: const Icon(Icons.refresh_rounded)),
          ],
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) {
              if (i == 2) _markSeen();
            },
            tabs: [
              const Tab(text: 'داشبورد'),
              const Tab(text: 'ارسال'),
              Tab(text: unread > 0 ? 'دریافتی (${Jalali.digits(unread)})' : 'دریافتی'),
              const Tab(text: 'اتصال'),
            ],
          ),
        ),
        body: Builder(builder: (tabContext) {
          _tabs = DefaultTabController.of(tabContext);
          return Column(children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: TabBarView(children: [
                _dashboard(),
                _sendTab(),
                _inboxTab(),
                _connectionTab(),
              ]),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _needSetup() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.link_off_rounded, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 10),
            const Text('ابتدا در زبانه «اتصال» نام کاربری و کلید وب‌سرویس ملی پیامک را وارد کنید.', textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _dashboard() {
    if (api == null) return _needSetup();
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
                colors: [Color(0xFF305F91), Color(0xFF14213D)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70),
              const SizedBox(width: 8),
              const Expanded(child: Text('اعتبار پنل', style: TextStyle(color: Colors.white70))),
              Text('خط ${Jalali.digits(line)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Text(credit == null ? '—' : '${Jalali.digits(credit!.toStringAsFixed(credit! % 1 == 0 ? 0 : 1))} پیامک',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
            if (error != null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('اعتبار فعلی تأیید نشده است.', style: TextStyle(color: Colors.white70)),
              ),
            if (credit != null && credit! < 50)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('اعتبار رو به اتمام است؛ پنل را شارژ کنید.', style: TextStyle(color: Color(0xFFFFE2A8), fontSize: 12)),
              ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44),
                      backgroundColor: const Color(0xFFFFD27A), foregroundColor: const Color(0xFF3A2A05)),
                  onPressed: () => _openUrl(MeliPayamak.panelUrl),
                  icon: const Icon(Icons.add_card_rounded, size: 19),
                  label: const Text('شارژ پنل'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54)),
                  onPressed: () => _openUrl(MeliPayamak.chargeUrl),
                  icon: const Icon(Icons.sell_outlined, size: 19),
                  label: const Text('تعرفه‌ها'),
                ),
              ),
            ]),
          ]),
        ),
        if (error != null)
          Card(
            color: scheme.errorContainer,
            margin: const EdgeInsets.only(top: 12),
            child: ListTile(leading: Icon(Icons.error_outline, color: scheme.onErrorContainer), title: Text(error!)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _kpi('دریافتی', inbox.length, Icons.move_to_inbox_rounded)),
          const SizedBox(width: 10),
          Expanded(child: _kpi('خوانده‌نشده', unread, Icons.mark_email_unread_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _kpi('ارسالی', sent.length, Icons.outbox_rounded)),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('تازه‌ترین پیام‌های دریافتی', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            if (inbox.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('پیامی دریافت نشده است.')),
            for (final m in inbox.take(5)) _messageTile(m),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
          'شارژ اعتبار با پرداخت امن در سایت ملی پیامک انجام می‌شود؛ پیامیار اطلاعات کارت بانکی دریافت نمی‌کند.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ]),
    );
  }

  Widget _kpi(String label, int value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(Jalali.digits(value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ]),
        ),
      );

  Widget _messageTile(PanelMessage m, {bool outgoing = false}) {
    final isNew = !outgoing && m.id > seenMax;
    return ListTile(
      leading: CircleAvatar(child: Icon(outgoing ? Icons.call_made_rounded : Icons.call_received_rounded, size: 18)),
      title: Row(children: [
        Expanded(
          child: Text(Jalali.digits(outgoing ? m.receiver : m.sender),
              textDirection: TextDirection.ltr, textAlign: TextAlign.right,
              style: TextStyle(fontWeight: isNew ? FontWeight.w900 : FontWeight.w600)),
        ),
        if (m.date != null) Text(Jalali.short(m.date!), style: const TextStyle(fontSize: 11)),
      ]),
      subtitle: Text(m.body, maxLines: 3, overflow: TextOverflow.ellipsis),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(outgoing ? 'به ${m.receiver}' : 'از ${m.sender}', textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              SelectableText(m.body),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: m.body));
                      Navigator.pop(ctx);
                      _notice('متن کپی شد.');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('کپی'),
                  ),
                ),
                if (!outgoing) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: () {
                        toField.text = m.sender;
                        Navigator.pop(ctx);
                        _tabs?.animateTo(1);
                      },
                      icon: const Icon(Icons.reply_rounded),
                      label: const Text('پاسخ از پنل'),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pickRecipients() async {
    try {
      final contacts = await SmsBridge.listContacts();
      if (!mounted) return;
      final current = toField.text.split(RegExp(r'[\s,،;]+'))
          .map(MeliPayamak.normalize).where((n) => n.isNotEmpty).toSet();
      final picked = await showContactPicker(context, contacts: contacts,
          selected: current, maxSelection: 100);
      if (picked == null || !mounted) return;
      final valid = picked.map(MeliPayamak.normalize).where((n) => n.isNotEmpty).toSet();
      toField.text = valid.join(', ');
      if (valid.length != picked.length) {
        _notice('فقط شماره‌های معتبر تلفن همراه برای پنل انتخاب شدند.');
      }
    } catch (_) {
      _notice('دسترسی مخاطبین پیامیار را از تنظیمات اندروید فعال کنید.');
    }
  }

  Future<void> _pickGroupRecipients() async {
    // Groups are local broadcast lists. Never auto-send as part of selection.
    final groups = (await SharedPreferences.getInstance()).getStringList(
      SmsGroupStore.storageKey) ?? const <String>[];
    final available = <SmsGroup>[];
    for (final json in groups) {
      try {
        final g = SmsGroup.fromJson(jsonDecode(json) as Map<String, dynamic>);
        if (g.recipients.isNotEmpty) available.add(g);
      } catch (_) {}
    }
    if (!mounted) return;
    if (available.isEmpty) {
      _notice('هنوز گروهی ندارید؛ از بخش «گروه‌ها» یک گروه بسازید.');
      return;
    }
    final chosen = await showModalBottomSheet<SmsGroup>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('انتخاب گروه پیامکی پیامیار')),
          for (final g in available)
            ListTile(title: Text(g.name),
              subtitle: Text('${g.recipients.length} عضو'),
              leading: const Icon(Icons.groups_rounded),
              onTap: () => Navigator.pop(ctx, g)),
        ],
      )),
    );
    if (chosen == null) return;
    final previous = toField.text.split(RegExp(r'[\s,،;]+'));
    final valid = {...previous, ...chosen.recipients}
        .map(MeliPayamak.normalize).where((n) => n.isNotEmpty).toSet();
    if (valid.length > 100) {
      _notice('پنل ملی پیامک در هر درخواست حداکثر ۱۰۰ گیرنده می‌پذیرد.');
      return;
    }
    toField.text = valid.join(', ');
  }

  Future<String?> _readTxt() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['txt'],
      );
      if (file == null) return null;
      // Check the size before reading the file into memory.
      final length = file.lengthSync() ?? await file.length();
      if (!file.name.toLowerCase().endsWith('.txt') ||
          length == null || length > 1024 * 1024) {
        _notice('فقط فایل TXT تا حجم یک مگابایت پذیرفته می‌شود.');
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _notice('فایل خالی است یا قابل خواندن نیست.');
        return null;
      }
      final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
      if (text.contains('\u0000')) {
        _notice('این فایل متن ساده TXT نیست.');
        return null;
      }
      return text;
    } catch (_) {
      _notice('خواندن TXT ناموفق بود. دسترسی انتخاب فایل را بررسی کنید.');
      return null;
    }
  }

  Future<void> _importTxtRecipients() async {
    final data = await _readTxt();
    if (data == null || !mounted) return;
    // One mobile number per line, or comma/semicolon separated.
    final parts = data.split(RegExp(r'[\s,،;]+')).where((v) => v.trim().isNotEmpty);
    final normalized = parts.map(MeliPayamak.normalize).where((n) => n.isNotEmpty).toSet();
    final current = toField.text.split(RegExp(r'[\s,،;]+'))
        .map(MeliPayamak.normalize).where((n) => n.isNotEmpty).toSet();
    final numbers = {...current, ...normalized};
    if (normalized.isEmpty) {
      _notice('شماره موبایل معتبری در فایل پیدا نشد.');
      return;
    }
    if (numbers.length > 100) {
      _notice('در هر ارسال از پنل حداکثر ۱۰۰ گیرنده مجاز است. فایل را تقسیم کنید.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context, builder: (ctx) => AlertDialog(
        title: const Text('پیش‌نمایش گیرنده‌های TXT'),
        content: Text('${Jalali.digits(normalized.length)} شماره معتبر در فایل یافت شد. '
          '${Jalali.digits(numbers.length)} شماره یکتا همراه گیرنده‌های قبلی ثبت می‌شود. '
          'هیچ پیامکی در این مرحله ارسال نخواهد شد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('افزودن گیرنده‌ها')),
        ],
      ),
    );
    if (confirmed == true && mounted) toField.text = numbers.join(', ');
  }

  Future<void> _importTxtMessage() async {
    final data = await _readTxt();
    if (data == null || !mounted) return;
    final body = data.trim();
    if (body.isEmpty) {
      _notice('فایل متن پیام خالی است.');
      return;
    }
    if (body.length > 5000) {
      _notice('متن فایل طولانی است؛ حداکثر ۵۰۰۰ نویسه برای پیش‌نویس مجاز است.');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context, builder: (ctx) => AlertDialog(
        title: const Text('پیش‌نمایش متن TXT'),
        content: SingleChildScrollView(child: SelectableText(body,
          maxLines: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(textField.text.isEmpty ? 'افزودن به متن پیام' : 'جایگزینی متن قبلی')),
        ],
      ),
    );
    if (accepted == true && mounted) textField.text = body;
  }

  Widget _sendTab() {
    if (api == null) return _needSetup();
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([textField, toField]),
      builder: (context, _) {
        final parts = _parts(textField.text);
        final count = toField.text.split(RegExp(r'[\s,،;]+')).map(MeliPayamak.normalize).where((n) => n.isNotEmpty).toSet().length;
        return ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: toField,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'گیرنده‌ها (با ویرگول یا خط جدید جدا کنید)',
              prefixIcon: const Icon(Icons.people_alt_outlined),
              suffixIcon: IconButton(
                tooltip: 'انتخاب از مخاطبین خود پیامیار',
                icon: const Icon(Icons.contacts_rounded),
                onPressed: _pickRecipients,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _pickGroupRecipients,
              icon: const Icon(Icons.groups_rounded),
              label: const Text('افزودن گیرنده از گروه‌های پیامیار'),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _importTxtRecipients,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('واردکردن شماره‌ها از فایل TXT'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: textField,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'متن پیامک', alignLabelWithHint: true),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _importTxtMessage,
              icon: const Icon(Icons.description_outlined),
              label: const Text('خواندن متن پیام از فایل TXT'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              '${Jalali.digits(textField.text.length)} نویسه • ${Jalali.digits(parts)} بخش • ${Jalali.digits(count)} گیرنده'
              '${count > 1 ? ' • برای ارسال گروهی «لغو11» را در انتهای متن بگذارید' : ''}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (count > 1 && !textField.text.contains('لغو11'))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => textField.text = '${textField.text.trimRight()}\nلغو11',
                icon: const Icon(Icons.add_rounded),
                label: const Text('افزودن «لغو11»'),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('پیامک فلش (نمایش مستقیم روی صفحه)'),
            value: flash,
            onChanged: (v) => setState(() => flash = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: sending ? null : _send,
            icon: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text('ارسال از خط ${Jalali.digits(line)}'),
          ),
          if (lastRecId != null)
            Card(
              margin: const EdgeInsets.only(top: 14),
              child: ListTile(
                leading: const Icon(Icons.receipt_long_rounded),
                title: Text('آخرین ارسال: $lastRecId', textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                subtitle: Text(lastDelivery ?? 'برای دیدن وضعیت تحویل، «بررسی» را بزنید'),
                trailing: TextButton(onPressed: _checkDelivery, child: const Text('بررسی')),
              ),
            ),
          if (sent.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
              child: Text('ارسال‌های اخیر پنل', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            Card(child: Column(children: [for (final m in sent.take(20)) _messageTile(m, outgoing: true)])),
          ],
        ]);
      },
    );
  }

  Widget _inboxTab() {
    if (api == null) return _needSetup();
    return RefreshIndicator(
      onRefresh: () async {
        await _refresh();
        await _markSeen();
      },
      child: inbox.isEmpty
          ? ListView(children: const [
              Padding(padding: EdgeInsets.all(40), child: Center(child: Text('پیامی به این خط نرسیده است.'))),
            ])
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: inbox.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) => _messageTile(inbox[i]),
            ),
    );
  }

  Widget _connectionTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              controller: userField,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'نام کاربری پنل', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passField,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: api == null ? 'کلید وب‌سرویس (API Key)' : 'کلید وب‌سرویس (خالی = بدون تغییر)',
                prefixIcon: const Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lineField,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'شماره خط', prefixIcon: Icon(Icons.sim_card_outlined)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: loading ? null : _saveCredentials,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('ذخیره و آزمایش اتصال'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'کلید وب‌سرویس را از پنل ملی پیامک › تنظیمات › وب‌سرویس بگیرید. اطلاعات با رمزنگاری Keystore فقط روی همین گوشی '
        'ذخیره و فقط به rest.payamak-panel.com فرستاده می‌شود. اگر پنل خطای «IP مجاز» داد، محدودیت IP وب‌سرویس را در پنل بردارید.',
        style: TextStyle(fontSize: 12, height: 1.8, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      if (user.isNotEmpty)
        Text('حساب متصل: $user', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: scheme.error, minimumSize: const Size.fromHeight(48)),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('خروج از حالت مدیر'),
              content: const Text('اطلاعات اتصال و رمز مدیر از این گوشی پاک می‌شود و ورودی پنل از تنظیمات پنهان می‌شود.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پاک کردن')),
              ],
            ),
          );
          if (ok != true) return;
          await AdminAccess.reset();
          if (!mounted) return;
          _notice('حالت مدیر غیرفعال شد.');
          Navigator.of(context).pop();
        },
        icon: const Icon(Icons.logout_rounded),
        label: const Text('خروج از حالت مدیر و پاک کردن اطلاعات'),
      ),
    ]);
  }
}
