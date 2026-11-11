import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'message_logic.dart';
import 'update_service.dart';
import 'brand_mark.dart';
import 'finance_logic.dart';
import 'sms_bridge.dart';
import 'conversation_logic.dart';

void main() => runApp(const PayamYar());
const brand = Color(0xFF087F81);
class PayamYar extends StatefulWidget {
  const PayamYar({super.key});
  @override State<PayamYar> createState() => _PayamYarState();
}
class _PayamYarState extends State<PayamYar> {
  final colors = const [brand, Color(0xFF305F91), Color(0xFF75539A), Color(0xFF9F5369), Color(0xFF47765F), Color(0xFFA17A37)];
  int palette = 0; ThemeMode mode = ThemeMode.system;
  double scale = 1; bool dense = false; bool hideText = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      palette = (p.getInt('palette') ?? 0).clamp(0, 5).toInt();
      mode = ThemeMode.values[(p.getInt('theme') ?? 0).clamp(0, 2).toInt()];
      scale = (p.getDouble('scale') ?? 1).clamp(.85, 1.3).toDouble();
      dense = p.getBool('dense') ?? false;
      hideText = p.getBool('privatePreview') ?? false;
    });
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('palette', palette);
    await p.setInt('theme', mode.index);
    await p.setDouble('scale', scale);
    await p.setBool('dense', dense);
    await p.setBool('privatePreview', hideText);
  }
  @override Widget build(BuildContext context) {
    ThemeData theme(Brightness b) {
      final s = ColorScheme.fromSeed(seedColor: colors[palette], brightness: b);
      return ThemeData(useMaterial3: true, colorScheme: s,
        fontFamily: 'Vazirmatn',
        scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF121F24) : const Color(0xFFF8F7F2),
        cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18), side: BorderSide(color: s.outlineVariant))),
        inputDecorationTheme: InputDecorationTheme(filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)));
    }
    return MaterialApp(
      title: 'پیامیار', debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light), darkTheme: theme(Brightness.dark), themeMode: mode,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl,
        child: MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale)), child: child!)),
      home: HomeScreen(colors: colors,
        settings: SettingsState(palette, mode, scale, dense, hideText),
        onSettings: (s) { setState(() {
          palette = s.palette; mode = s.mode; scale = s.scale;
          dense = s.dense; hideText = s.hideText;
        }); _save(); }),
    );
  }
}
class SettingsState {
  final int palette; final ThemeMode mode; final double scale;
  final bool dense; final bool hideText;
  const SettingsState(this.palette, this.mode, this.scale, this.dense, this.hideText);
}
class HomeScreen extends StatefulWidget {
  final SettingsState settings; final ValueChanged<SettingsState> onSettings;
  final List<Color> colors;
  const HomeScreen({super.key, required this.settings, required this.onSettings, required this.colors});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int tab = 0; String query = ''; MessageCategory? filter;
  DateTimeRange? searchRange;
  bool checking = false;
  bool smsLoading = false;
  bool smsPermissionGranted = false;
  bool smsAvailable = false;
  bool defaultSms = false;
  bool loadingOlder = false;
  bool hasOlder = false;
  bool submitting = false;
  int selectedSim = -1;
  List<Map<dynamic, dynamic>> sims = [];
  String? queuedId;
  Timer? refreshDebounce;
  final archived = <String>{};
  bool showArchive = false;
  bool unreadOnly = false;
  String? smsError;
  List<MessageRecord> phoneMessages = [];
  List<MessageRecord> get displayedMessages => SmsBridge.supported ? phoneMessages : demo;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreDraft();
    if (SmsBridge.supported) SmsBridge.listen((event) async {
      if (event == 'composeIntent') { await _takeIntent(); return; }
      refreshDebounce?.cancel();
      refreshDebounce = Timer(const Duration(milliseconds: 400), _refreshSms);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkForUpdates(silent: true);
        _refreshSms();
        _takeIntent();
      }
    });
  }
  final recipient = TextEditingController(), message = TextEditingController();
  Timer? countdown; int remaining = 0; MessageRecord? pending;
  final demo = <MessageRecord>[
    MessageRecord(sender:'هنر مردمی', body:'به پیامیار خوش آمدید. این پیام نمونه است.', date:DateTime(2026,11,11,10)),
    MessageRecord(sender:'بانک نمونه', body:'واریز ۲۵۰,۰۰۰ تومان به حساب نمونه؛ پیام آزمایشی.', date:DateTime(2026,11,11,9)),
    MessageRecord(sender:'اپراتور', body:'بسته اینترنت شما فعال شد.', date:DateTime(2026,11,10)),
    MessageRecord(sender:'فروشگاه نمونه', body:'تخفیف ویژه امروز؛ تبلیغ آزمایشی.', date:DateTime(2026,11,9)),
  ];


  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { _refreshSms(); _takeIntent(); }
    if (state == AppLifecycleState.paused) _saveDraft();
  }
  Future<void> _restoreDraft() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    recipient.text = p.getString('draft_to') ?? '';
    message.text = p.getString('draft_body') ?? '';
    archived.addAll(p.getStringList('archived') ?? []);
    final id = p.getString('last_queue');
    if (SmsBridge.supported && id != null) {
      final state = await SmsBridge.sendStatus(id);
      if (mounted && state.startsWith('send_failed')) _notice('ارسال قبلی ناموفق بود؛ متن پیش‌نویس حفظ شده است.');
      if ((state == 'accepted_by_radio' || state == 'delivered') &&
          recipient.text == p.getString('last_queue_to') && message.text == p.getString('last_queue_body')) {
        recipient.clear(); message.clear(); await _saveDraft();
        await p.remove('last_queue');
      }
    }
    if (mounted) setState(() {});
  }
  Future<void> _saveDraft() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('draft_to', recipient.text);
    await p.setString('draft_body', message.text);
    await p.setStringList('archived', archived.toList());
  }
  void _notice(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  Future<void> _takeIntent() async {
    if (!SmsBridge.supported) return;
    final value = await SmsBridge.composeIntent();
    if (value == null || !mounted) return;
    recipient.text = value['to']?.toString() ?? '';
    message.text = value['body']?.toString() ?? '';
    _compose();
  }
  Future<void> _makeDefault() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('پیامک‌رسان پیش‌فرض'),
      content: const Text('پیامیار مسئول دریافت و نگهداری SMS می‌شود و می‌تواند پیام‌ها را حذف یا خوانده‌شده کند. این نسخه MMS (عکس و پیام چندرسانه‌ای) را دانلود و ارسال نمی‌کند. اگر MMS استفاده می‌کنید، برنامه فعلی را پیش‌فرض نگه دارید.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('فعلاً نه')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('انتخاب برای SMS'))]));
    if (ok == true) await SmsBridge.requestDefault();
  }
  Future<void> _older() async {
    if (loadingOlder || smsLoading || phoneMessages.isEmpty) return;
    setState(() => loadingOlder = true);
    try {
      final rows = await SmsBridge.read(before: phoneMessages.last);
      if (mounted) setState(() { phoneMessages.addAll(rows); hasOlder = rows.length == 500; });
    } catch (_) { _notice('بارگذاری پیام‌های قدیمی‌تر انجام نشد.'); }
    finally { if (mounted) setState(() => loadingOlder = false); }
  }

  Future<void> _refreshSms() async {
    if (!mounted || !SmsBridge.supported || smsLoading || loadingOlder) return;
    setState(() { smsLoading = true; smsError = null; });
    try {
      final available = await SmsBridge.available();
      final status = await SmsBridge.status();
      if (!mounted) return;
      List<MessageRecord> messages = [];
      if (available && status.canRead) {
        messages = await SmsBridge.read(limit: 500);
        final target = phoneMessages.length;
        var page = messages;
        while (page.length == 500 && messages.length < target) {
          page = await SmsBridge.read(before: messages.last);
          messages.addAll(page);
        }
        hasOlder = page.length == 500;
        sims = await SmsBridge.subscriptions();
        if (!sims.any((s) => s['id'] == selectedSim)) selectedSim = -1;
      }
      if (!mounted) return;
      setState(() {
        defaultSms = status.isDefault;
        smsAvailable = available;
        smsPermissionGranted = status.canRead;
        phoneMessages = messages;
      });
    } catch (_) {
      if (mounted) setState(() => smsError = 'دریافت پیامک از گوشی ممکن نشد.');
    } finally {
      if (mounted) setState(() => smsLoading = false);
    }
  }

  Future<void> _requestSmsPermission() async {
    if (!SmsBridge.supported) return;
    try {
      await SmsBridge.request();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('دسترسی‌ها را در پنجره اندروید تأیید کنید؛ پیام‌ها پس از بازگشت بارگذاری می‌شوند.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('درخواست مجوز پیامک انجام نشد.')));
      }
    }
  }

  Future<void> _checkForUpdates({bool silent = false}) async {
    if (checking) return;
    setState(() => checking = true);
    try {
      final result = await UpdateService.check();
      if (!mounted) return;
      final msg = !result.available
          ? 'در حال حاضر نسخه منتشرشده جدیدی وجود ندارد.'
          : 'نسخه جدید: ${result.version}';
      if (!result.available || result.url.isEmpty) {
        if (!silent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('به‌روزرسانی پیامیار'),
            content: Text('$msg\n${result.notes}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بعداً')),
              FilledButton(onPressed: () {
                Navigator.pop(ctx);
                UpdateService.openDownload(result.url);
              }, child: const Text('دریافت نسخه معتبر')),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('بررسی نسخه ممکن نیست؛ اتصال اینترنت را بررسی کنید.')));
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SmsBridge.stopListening(); refreshDebounce?.cancel(); countdown?.cancel();
    recipient.dispose(); message.dispose(); super.dispose();
  }
  Future<void> _queue() async {
    if (pending != null || submitting || recipient.text.trim().isEmpty || message.text.trim().isEmpty) return;
    submitting = true;
    final item = MessageRecord(sender: recipient.text.trim(), body: message.text.trim(), date: DateTime.now(), outgoing: true);
    try {
      await _saveDraft();
      if (SmsBridge.supported) {
        queuedId = await SmsBridge.queue(item.sender, item.body, selectedSim);
        final p = await SharedPreferences.getInstance();
        await p.setString('last_queue', queuedId!);
        await p.setString('last_queue_to', item.sender);
        await p.setString('last_queue_body', item.body);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() { pending = item; remaining = 5; tab = 0; });
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      countdown?.cancel();
      countdown = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
        if (!mounted) { timer.cancel(); return; }
        final left = deadline.difference(DateTime.now()).inMilliseconds;
        if (left > 0) { setState(() => remaining = (left / 1000).ceil()); return; }
        timer.cancel();
        setState(() => remaining = 0);
        await _watchSend(item);
      });
    } on PlatformException catch (e) { _notice(e.message ?? 'ارسال ممکن نشد.'); }
    catch (_) { _notice('ارسال ممکن نشد؛ متن پیش‌نویس حفظ شده است.'); }
    finally { submitting = false; }
  }
  Future<void> _watchSend(MessageRecord item) async {
    if (SmsBridge.supported) {
      try {
        String state = 'queued';
        for (var attempt = 0; attempt < 15 && (state == 'queued' || state == 'pending'); attempt++) {
          state = await SmsBridge.sendStatus(queuedId!);
          if (state == 'queued' || state == 'pending') await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!mounted) return;
        if (state == 'accepted_by_radio' || state == 'delivered') {
          recipient.clear(); message.clear(); await _saveDraft();
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('last_queue');
          _notice(state == 'delivered' ? 'پیام تحویل داده شد.' : 'ارسال تأیید شد؛ گزارش تحویل در گفتگو نمایش داده می‌شود.');
        } else if (state.startsWith('send_failed')) {
          _notice('ارسال ناموفق بود؛ پیش‌نویس حفظ شده است. سیم‌کارت و مجوزها را بررسی کنید.');
        } else { _notice('وضعیت ارسال هنوز قطعی نیست؛ پیش از ارسال مجدد، گفتگو را بررسی کنید.'); }
        await _refreshSms();
      } catch (_) { _notice('وضعیت ارسال دریافت نشد؛ پیش از تلاش مجدد گفتگو را بررسی کنید.'); }
    } else {
      demo.insert(0, item); recipient.clear(); message.clear();
      _notice('پیام فقط به فهرست نمونه ویندوز افزوده شد.');
    }
    if (mounted) setState(() { pending = null; remaining = 0; });
  }
  Future<void> _undo() async {
    if (remaining <= 0) return;
    if (SmsBridge.supported && !await SmsBridge.cancel(queuedId!)) {
      _notice('مهلت لغو تمام شده است.'); return;
    }
    countdown?.cancel();
    if (mounted) setState(() { pending = null; remaining = 0; });
    _notice('ارسال لغو شد؛ متن در پیش‌نویس باقی ماند.');
  }
  void _compose() {
    if (pending != null) return;
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.viewInsetsOf(ctx).bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('پیام جدید', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(SmsBridge.supported
              ? 'ارسال SMS با هزینه اپراتور؛ تا ۵ ثانیه قابل لغو است. در پس‌زمینه ممکن است اندروید ارسال را به تأخیر بیندازد.'
              : 'ارسال در نسخه ویندوز فعلاً فقط نمایشی است.'),
          const SizedBox(height: 16),
          if (SmsBridge.supported && sims.isNotEmpty)
            DropdownButtonFormField<int>(initialValue: selectedSim,
              decoration: const InputDecoration(labelText: 'سیم‌کارت ارسال'),
              items: sims.map((s) => DropdownMenuItem<int>(value: s['id'] as int, child: Text(s['label'].toString()))).toList(),
              onChanged: (v) => selectedSim = v ?? -1),
          const SizedBox(height: 12),
          TextField(controller: recipient, textDirection: TextDirection.ltr, onChanged: (_) => _saveDraft(), keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'شماره گیرنده', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: message, onChanged: (_) => _saveDraft(), maxLength: 2000, minLines: 3, maxLines: 5,
            decoration: const InputDecoration(labelText: 'متن پیام')),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _queue, icon: const Icon(Icons.send_outlined),
            label: const Text('ارسال با فرصت لغو ۵ ثانیه‌ای')),
        ])));
  }
  @override Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      appBar: AppBar(title: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
          child: const BrandMark()),
        const SizedBox(width: 11),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('پیامیار', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('از خانواده هنر مردمی', style: TextStyle(fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ]), actions: [
        IconButton(tooltip: 'تنظیمات ظاهر', icon: const Icon(Icons.palette_outlined),
          onPressed: () => setState(() => tab = 2)),
      ]),
      body: Row(children: [
        if (wide) NavigationRail(selectedIndex: tab,
          labelType: NavigationRailLabelType.all,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.forum_outlined), label: Text('پیام‌ها')),
            NavigationRailDestination(icon: Icon(Icons.insights_outlined), label: Text('گزارش‌ها')),
            NavigationRailDestination(icon: Icon(Icons.grid_view_outlined), label: Text('بیشتر')),
          ]),
        Expanded(child: Align(alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 950),
            child: tab == 0 ? _messages() : tab == 1 ? _reports() : _more()))),
      ]),
      floatingActionButton: tab == 0 ? FloatingActionButton.extended(
        onPressed: _compose, icon: const Icon(Icons.edit_outlined), label: const Text('پیام جدید')) : null,
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'پیام‌ها'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'گزارش‌ها'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'بیشتر'),
        ]),
    );
  }
  String _name(MessageCategory c) => switch (c) {
    MessageCategory.personal => 'شخصی', MessageCategory.banking => 'بانکی',
    MessageCategory.service => 'خدماتی', MessageCategory.advertising => 'تبلیغاتی',
  };
  IconData _icon(MessageCategory c) => switch (c) {
    MessageCategory.personal => Icons.person_outline,
    MessageCategory.banking => Icons.account_balance_outlined,
    MessageCategory.service => Icons.receipt_long_outlined,
    MessageCategory.advertising => Icons.campaign_outlined,
  };
  Widget _messages() {
    final entries = MessageLogic.search(displayedMessages, query,
      from: searchRange?.start,
      to: searchRange == null ? null : DateTime(searchRange!.end.year,
        searchRange!.end.month, searchRange!.end.day, 23, 59, 59, 999)).where(
      (m) => filter == null || MessageLogic.category(m) == filter).toList();
    final conversations = ConversationLogic.group(entries).where((c) =>
      archived.contains(ConversationLogic.normalize(c.address)) == showArchive &&
      (!unreadOnly || c.messages.any((m) => !m.read && !m.outgoing))).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
      Container(padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF075D63), brand, Color(0xFF27536B)]),
          borderRadius: BorderRadius.circular(24)),
        child: Stack(children: [
          Positioned(left: 0, top: -24, child: Icon(Icons.auto_awesome_mosaic,
            size: 105, color: Colors.white.withValues(alpha: .12))),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('پیام‌هایت، مرتب و امن', style: TextStyle(
              color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            SizedBox(height: 7),
            Text('سادگی امروز، اصالت دیروز', style: TextStyle(color: Color(0xFFF5DBA5))),
            SizedBox(height: 10),
            Text('پیامیار • اطلاعات روی دستگاه شما', style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ])),
      if (SmsBridge.supported) ...[
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Icon(smsPermissionGranted ? Icons.verified_user_outlined : Icons.shield_outlined),
          const SizedBox(width: 9),
          Expanded(child: Text(smsLoading
              ? 'در حال خواندن پیامک‌ها...'
              : smsPermissionGranted
                  ? 'پیامک‌های گوشی • فقط روی دستگاه'
                  : smsAvailable ? 'برای دیدن پیامک‌های خود دسترسی را فعال کنید.'
                      : 'این گوشی قابلیت پیامک ندارد.')),
          if (smsAvailable)
            TextButton(onPressed: _requestSmsPermission, child: Text(smsPermissionGranted ? 'مجوزها' : 'فعال‌سازی')),
          IconButton(tooltip: 'تازه‌سازی پیامک‌ها', onPressed: _refreshSms,
            icon: const Icon(Icons.refresh)),
        ]))),
        if (smsAvailable && !defaultSms)
          Card(child: ListTile(title: const Text('فعال‌سازی مدیریت کامل SMS'),
            subtitle: const Text('دریافت پس‌زمینه، حذف و خوانده‌شده؛ نیازمند انتخاب پیش‌فرض'),
            trailing: const Icon(Icons.chevron_left), onTap: _makeDefault)),
        if (smsError != null) Padding(padding: const EdgeInsets.all(8),
          child: Text(smsError!, style: const TextStyle(color: Colors.red))),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        FilterChip(label: const Text('خوانده‌نشده'), selected: unreadOnly, onSelected: (v) => setState(() => unreadOnly = v)),
        FilterChip(label: const Text('بایگانی'), selected: showArchive, onSelected: (v) => setState(() => showArchive = v)),
      ]),
      if (hasOlder) TextButton.icon(onPressed: loadingOlder ? null : _older,
        icon: const Icon(Icons.history), label: Text(loadingOlder ? 'در حال بارگذاری...' : 'بارگذاری پیام‌های قدیمی‌تر برای نمایش و جستجو')),
      const SizedBox(height: 17),
      TextField(onChanged: (v) => setState(() => query = v),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search), hintText: 'جستجو در پیام‌ها و فرستنده‌ها')),
      const SizedBox(height: 8),
      Row(children: [
        TextButton.icon(
          icon: const Icon(Icons.date_range_outlined),
          label: Text(searchRange == null ? 'فیلتر تاریخ' : 'بازه تاریخ انتخاب شد'),
          onPressed: () async {
            final value = await showDateRangePicker(
              context: context, firstDate: DateTime(2010),
              lastDate: DateTime(2100),
              initialDateRange: searchRange,
            );
            if (value != null && mounted) setState(() => searchRange = value);
          },
        ),
        if (searchRange != null)
          IconButton(
            tooltip: 'حذف فیلتر تاریخ', icon: const Icon(Icons.close),
            onPressed: () => setState(() => searchRange = null),
          ),
      ]),
      const SizedBox(height: 12),
      SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: [
        Padding(padding: const EdgeInsets.only(left: 7),
          child: ChoiceChip(label: const Text('همه'), selected: filter == null,
            onSelected: (_) => setState(() => filter = null))),
        for (final c in MessageCategory.values)
          Padding(padding: const EdgeInsets.only(left: 7),
            child: ChoiceChip(label: Text(_name(c)), selected: filter == c,
              onSelected: (_) => setState(() => filter = c))),
      ])),
      if (pending != null) ...[
        const SizedBox(height: 14),
        Card(color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Icon(Icons.schedule_send_outlined), const SizedBox(width: 8),
            Expanded(child: Text(remaining > 0 ? 'ارسال تا $remaining ثانیه دیگر' : 'در انتظار تأیید ارسال…')),
            TextButton(onPressed: remaining > 0 ? _undo : null, child: const Text('لغو ارسال')),
          ]))),
      ],
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('گفتگوها', style: Theme.of(context).textTheme.titleLarge),
        Text('${conversations.length} گفتگو',
          style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 12),
      for (final conversation in conversations) ...[
        Builder(builder: (context) {
          final m = conversation.latest;
          return
        Card(child: ListTile(
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14, vertical: widget.settings.dense ? 0 : 8),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(_icon(MessageLogic.category(m)))),
          title: Text('${m.sender}${conversation.messages.any((m) => !m.read && !m.outgoing) ? ' • جدید' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(widget.settings.hideText ? 'متن پیام مخفی است' :
            conversation.count > 1 ? '${m.body} • ${conversation.count} پیام' : m.body,
            maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: MessageLogic.suspicious(m.body)
            ? const Icon(Icons.warning_amber_outlined, color: Colors.orange)
            : const Icon(Icons.chevron_left),
          onTap: () => _openConversation(conversation),
        )); }),
        const SizedBox(height: 9),
      ],
      if (entries.isEmpty) const Padding(padding: EdgeInsets.all(24),
        child: Text('موردی پیدا نشد.')),
    ]);
  }
  void _openConversation(Conversation conversation) {
    if (defaultSms) {
      final ids = conversation.messages.where((m) => m.id != null && !m.read).map((m) => m.id!).toList();
      if (ids.isNotEmpty) SmsBridge.markRead(ids).then((_) => _refreshSms()).catchError((Object _) { _notice('تغییر وضعیت پیام انجام نشد.'); });
    }
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .7,
          child: Column(children: [
            Row(children: [
              Expanded(child: Text(conversation.address,
                style: Theme.of(ctx).textTheme.titleLarge)),
              IconButton(tooltip: showArchive ? 'خروج از بایگانی' : 'بایگانی', icon: const Icon(Icons.archive_outlined), onPressed: () {
                final key = ConversationLogic.normalize(conversation.address);
                setState(() { if (!archived.remove(key)) archived.add(key); });
                _saveDraft(); Navigator.pop(ctx);
              }),
              IconButton(tooltip: 'پاسخ', icon: const Icon(Icons.reply),
                onPressed: () {
                  Navigator.pop(ctx);
                  recipient.text = conversation.address;
                  message.clear();
                  _compose();
                }),
            ]),
            const Divider(),
            Expanded(child: ListView.builder(
              reverse: true,
              itemCount: conversation.messages.length,
              itemBuilder: (context, index) {
                final msg = conversation.messages[index];
                return Align(
                  alignment: msg.outgoing ? Alignment.centerLeft : Alignment.centerRight,
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: msg.outgoing
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SelectableText(msg.body),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'کپی', icon: const Icon(Icons.copy, size: 18), onPressed: () => Clipboard.setData(ClipboardData(text: msg.body))),
                          IconButton(tooltip: 'بازارسال', icon: const Icon(Icons.forward, size: 18), onPressed: () {
                            Navigator.pop(ctx); recipient.clear(); message.text = msg.body; _compose();
                          }),
                          if (defaultSms && msg.id != null)
                            IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () async {
                              final ok = await showDialog<bool>(context: ctx, builder: (dialog) => AlertDialog(
                                title: const Text('حذف پیام از گوشی؟'), content: const Text('این حذف دائمی است و در سایر پیامک‌رسان‌ها هم اعمال می‌شود.'),
                                actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('انصراف')),
                                  FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('حذف'))]));
                              if (ok != true) return;
                              try { await SmsBridge.delete([msg.id!]); if (ctx.mounted) Navigator.pop(ctx); await _refreshSms(); }
                              catch (_) { _notice('حذف انجام نشد؛ پیش‌فرض بودن پیامیار را بررسی کنید.'); }
                            }),
                        ]),
                        if (msg.outgoing) Text(msg.type == 5 ? 'ارسال ناموفق' : msg.type == 4 || msg.type == 6 ? 'در حال ارسال' : msg.delivery == 0 ? 'تحویل داده شد' : msg.delivery >= 64 ? 'تحویل ناموفق' : 'ارسال شده • تحویل تأیید نشده'),
                        const SizedBox(height: 4),
                        Text(msg.date.toLocal().toString().substring(0, 16),
                          style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    )),
                );
              },
            )),
          ]),
        ),
      ),
    );
  }
  Widget _feature(IconData icon, String title, String subtitle) => Card(
    child: ListTile(contentPadding: const EdgeInsets.all(14),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle)));
  Widget _reports() {
    final entries = FinanceLogic.extract(displayedMessages);
    final deposits = FinanceLogic.total(entries, FinanceKind.deposit);
    final withdrawals = FinanceLogic.total(entries, FinanceKind.withdrawal);
    final privateMode = widget.settings.hideText;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text('گزارش‌های هوشمند', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 7),
      const Text('تحلیل محلی پیام‌های در دسترس؛ هیچ پیامکی به سرور ارسال نمی‌شود.'),
      const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('خلاصه مالی برآوردی', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 13),
          Text('مجموع واریز: ${privateMode ? '••••' : FinanceLogic.formatTomans(deposits)}'),
          const SizedBox(height: 7),
          Text('مجموع برداشت: ${privateMode ? '••••' : FinanceLogic.formatTomans(withdrawals)}'),
          const SizedBox(height: 10),
          Text('${entries.length} تراکنش با قواعد ابتدایی شناسایی شد.',
            style: Theme.of(context).textTheme.bodySmall),
        ]))),
      const SizedBox(height: 12),
      _feature(Icons.shield_outlined, 'هشدار پیام‌های مشکوک',
        'شناسایی نشانه‌های رایج کلاهبرداری روی دستگاه؛ هشدار قطعی نیست.'),
      const SizedBox(height: 10),
      _feature(Icons.receipt_long_outlined, 'استخراج تراکنش‌ها',
        'پردازش ریال و تومان روی دستگاه؛ نتیجه باید توسط کاربر بررسی شود.'),
    ]);
  }
  Widget _more() {
    final s = widget.settings;
    void change({int? p, ThemeMode? m, double? sc, bool? d, bool? h}) =>
      widget.onSettings(SettingsState(p ?? s.palette, m ?? s.mode, sc ?? s.scale,
        d ?? s.dense, h ?? s.hideText));
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text('تنظیمات و امکانات', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('شخصی‌سازی', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 13),
          const Text('رنگ برنامه'),
          const SizedBox(height: 9),
          Wrap(spacing: 10, runSpacing: 9, children: [
            for (int i = 0; i < widget.colors.length; i++)
              Tooltip(message: 'رنگ شماره ${i + 1}',
                child: InkWell(onTap: () => change(p: i),
                  child: CircleAvatar(radius: 21, backgroundColor: widget.colors[i],
                    child: i == s.palette
                      ? const Icon(Icons.check, color: Colors.white) : null))),
          ]),
          const SizedBox(height: 18),
          const Text('حالت نمایش'),
          const SizedBox(height: 9),
          SegmentedButton<ThemeMode>(segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('خودکار')),
            ButtonSegment(value: ThemeMode.light, label: Text('روشن')),
            ButtonSegment(value: ThemeMode.dark, label: Text('تاریک')),
          ], selected: {s.mode}, onSelectionChanged: (v) => change(m: v.first)),
          const SizedBox(height: 12),
          Text('اندازه متن: ${(s.scale * 100).round()}٪'),
          Slider(value: s.scale, min: .85, max: 1.3, divisions: 9,
            onChanged: (v) => change(sc: v)),
          SwitchListTile(title: const Text('چیدمان فشرده'),
            value: s.dense, onChanged: (v) => change(d: v)),
          SwitchListTile(title: const Text('مخفی کردن پیش‌نمایش'),
            value: s.hideText, onChanged: (v) => change(h: v)),
        ]))),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.language_outlined),
        title: const Text('صفحه پیامیار در هنر مردمی'),
        subtitle: const Text('معرفی اپ، اطلاعات نسخه و راهنمای دریافت'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => UpdateService.openDownload('https://honarmardomi.ir/payamyar/'),
      )),
      const SizedBox(height: 10),
      _feature(Icons.phonelink_lock, 'اتصال گوشی و ویندوز',
        'در انتظار تکمیل جفت‌سازی رمزگذاری‌شده.'),
      const SizedBox(height: 10),
      _feature(Icons.backup_outlined, 'پشتیبان‌گیری امن',
        'در نسخه عملیاتی و پس از بررسی امنیت پیاده‌سازی می‌شود.'),
      const SizedBox(height: 10),
      const SizedBox(height: 10),
      Card(child: ListTile(
        leading: const Icon(Icons.system_update_outlined),
        title: const Text('بررسی به‌روزرسانی'),
        subtitle: const Text('دریافت نسخه معتبر با تأیید کاربر؛ بدون نصب خودکار'),
        trailing: checking ? const SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_left),
        onTap: checking ? null : _checkForUpdates,
      )),
      const SizedBox(height: 10),
      _feature(Icons.groups_outlined, 'ارسال گروهی',
        'نیازمند اتصال پیامک واقعی و تأیید هر نوبت ارسال است.'),
    ]);
  }
}

