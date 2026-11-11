import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'message_logic.dart';
import 'update_service.dart';
import 'brand_mark.dart';

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
class _HomeScreenState extends State<HomeScreen> {
  int tab = 0; String query = ''; MessageCategory? filter;
  bool checking = false;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkForUpdates(silent: true);
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
  @override void dispose() { countdown?.cancel(); recipient.dispose(); message.dispose(); super.dispose(); }
  void _queue() {
    if (pending != null || recipient.text.trim().isEmpty || message.text.trim().isEmpty) return;
    final item = MessageRecord(sender: recipient.text.trim(), body: message.text.trim(),
      date: DateTime.now(), outgoing: true);
    Navigator.of(context).pop();
    setState(() { pending = item; remaining = 5; tab = 0; });
    countdown?.cancel();
    countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (remaining > 1) { setState(() => remaining--); return; }
      timer.cancel();
      setState(() { demo.insert(0, item); pending = null; remaining = 0; });
      recipient.clear(); message.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('پیام به فهرست نمونه اضافه شد؛ SMS واقعی ارسال نشد.')));
    });
  }
  void _undo() {
    countdown?.cancel();
    setState(() { pending = null; remaining = 0; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ارسال نمونه لغو شد.')));
  }
  void _compose() {
    if (pending != null) return;
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.viewInsetsOf(ctx).bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('پیام جدید', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('ارسال در این نسخه فقط نمایشی است.'),
          const SizedBox(height: 16),
          TextField(controller: recipient, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'شماره گیرنده', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: message, minLines: 3, maxLines: 5,
            decoration: const InputDecoration(labelText: 'متن پیام')),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _queue, icon: const Icon(Icons.send_outlined),
            label: const Text('ارسال نمونه (لغو تا ۵ ثانیه)')),
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
    final entries = MessageLogic.search(demo, query).where(
      (m) => filter == null || MessageLogic.category(m) == filter).toList();
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
            Text('نسخه نمایشی • پیام‌های نمونه', style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ])),
      const SizedBox(height: 17),
      TextField(onChanged: (v) => setState(() => query = v),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search), hintText: 'جستجو در پیام‌ها و فرستنده‌ها')),
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
            Expanded(child: Text('ارسال نمونه تا $remaining ثانیه دیگر')),
            TextButton(onPressed: _undo, child: const Text('لغو ارسال')),
          ]))),
      ],
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('گفتگوها', style: Theme.of(context).textTheme.titleLarge),
        Text('${entries.length} پیام نمونه',
          style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 12),
      for (final m in entries) ...[
        Card(child: ListTile(
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14, vertical: widget.settings.dense ? 0 : 8),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(_icon(MessageLogic.category(m)))),
          title: Text(m.sender, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(widget.settings.hideText ? 'متن پیام مخفی است' : m.body,
            maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: MessageLogic.suspicious(m.body)
            ? const Icon(Icons.warning_amber_outlined, color: Colors.orange)
            : const Icon(Icons.chevron_left),
          onTap: () => showModalBottomSheet<void>(context: context,
            showDragHandle: true, builder: (ctx) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.sender, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14), Text(m.body),
                  const SizedBox(height: 16),
                  const Text('این داده نمایشی است؛ SMS واقعی خوانده نشده است.'),
                ]))),
        )),
        const SizedBox(height: 9),
      ],
      if (entries.isEmpty) const Padding(padding: EdgeInsets.all(24),
        child: Text('موردی پیدا نشد.')),
    ]);
  }
  Widget _feature(IconData icon, String title, String subtitle) => Card(
    child: ListTile(contentPadding: const EdgeInsets.all(14),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle)));
  Widget _reports() => ListView(padding: const EdgeInsets.all(18), children: [
    Text('گزارش‌های هوشمند', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 7),
    const Text('نمای ساده گزارش‌ها؛ محاسبات واقعی پس از اتصال پیامک فعال می‌شود.'),
    const SizedBox(height: 18),
    _feature(Icons.account_balance_wallet_outlined, 'تراکنش‌های مالی',
      'استخراج مبلغ، ریال و تومان در نسخه عملیاتی.'),
    const SizedBox(height: 10),
    _feature(Icons.shield_outlined, 'هشدار پیام‌های مشکوک',
      'فعلاً تنها قواعد ساده روی پیام‌های نمونه فعال است.'),
  ]);
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
