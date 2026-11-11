import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../sms_bridge.dart';
import '../update_service.dart';

class SettingsScreen extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  const SettingsScreen({super.key, required this.store, required this.settings});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool checking = false;
  AppStore get store => widget.store;
  AppSettings get settings => widget.settings;

  Future<void> _checkUpdate() async {
    setState(() => checking = true);
    try {
      final result = await UpdateService.check();
      if (!mounted) return;
      if (!result.available || result.url.isEmpty) {
        store.onNotice?.call('شما آخرین نسخه پیامیار را دارید.');
      } else {
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: Text('نسخه جدید ${Jalali.digits(result.version)}'),
          content: Text(result.notes),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بعداً')),
            TextButton(onPressed: () { Navigator.pop(ctx); UpdateService.openDownload(result.url); }, child: const Text('دریافت')),
          ]));
      }
    } catch (_) {
      store.onNotice?.call('بررسی به‌روزرسانی ممکن نشد؛ اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _templates() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('پیام‌های آماده', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final t in store.templates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t),
                trailing: IconButton(tooltip: 'حذف', icon: const Icon(Icons.close_rounded), onPressed: () => store.removeTemplate(t))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'متن پیام آماده جدید'))),
              const SizedBox(width: 8),
              IconButton.filled(tooltip: 'افزودن', icon: const Icon(Icons.add_rounded), onPressed: () {
                store.addTemplate(controller.text);
                controller.clear();
              }),
            ]),
          ]),
        ),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, settings]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('تنظیمات')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            if (SmsBridge.supported) ...[
              _section('پیامک'),
              Card(child: Column(children: [
                ListTile(
                  leading: Icon(store.isDefault ? Icons.verified_rounded : Icons.sms_outlined,
                    color: store.isDefault ? Colors.green : scheme.primary),
                  title: const Text('پیام‌رسان پیش‌فرض'),
                  subtitle: Text(store.isDefault ? 'پیامیار پیام‌رسان پیش‌فرض گوشی است' : 'فعال نیست؛ برای دریافت پیام‌های جدید فعال کنید'),
                  trailing: store.isDefault ? null : const Icon(Icons.chevron_left_rounded),
                  onTap: store.isDefault ? null : store.requestDefault),
                ListTile(
                  leading: Icon(Icons.lock_open_rounded, color: scheme.primary),
                  title: const Text('دسترسی‌های برنامه'),
                  subtitle: Text(store.permissions.contacts ? 'پیامک، مخاطبان و اعلان' : 'دسترسی مخاطبان داده نشده؛ نام‌ها نمایش داده نمی‌شوند'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () async {
                    final state = await store.requestPermissions();
                    if (state.canRead && state.contacts) {
                      store.onNotice?.call('همه دسترسی‌ها فعال است.');
                    } else {
                      await SmsBridge.openAppSettings();
                    }
                  }),
                ListTile(
                  leading: Icon(Icons.block_rounded, color: scheme.primary),
                  title: const Text('شماره‌های مسدود'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: SmsBridge.manageBlocked),
                ListTile(
                  leading: Icon(Icons.sync_rounded, color: scheme.primary),
                  title: const Text('بارگذاری دوباره همه پیام‌ها'),
                  subtitle: Text('${Jalali.digits(store.messages.length)} پیام روی گوشی'),
                  onTap: store.loadingAll ? null : store.loadAll),
              ])),
            ],
            _section('ظاهر'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('رنگ برنامه'),
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 10, children: [
                  for (var i = 0; i < palettes.length; i++)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => settings.update(palette: i),
                      child: CircleAvatar(radius: 20, backgroundColor: palettes[i],
                        child: i == settings.palette ? const Icon(Icons.check_rounded, color: Colors.white) : null)),
                ]),
                const SizedBox(height: 18),
                const Text('حالت نمایش'),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('خودکار')),
                    ButtonSegment(value: ThemeMode.light, label: Text('روشن')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('تاریک')),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (v) => settings.update(mode: v.first))),
                const SizedBox(height: 16),
                Text('اندازه متن: ${Jalali.digits((settings.scale * 100).round())}٪'),
                Slider(value: settings.scale, min: .85, max: 1.3, divisions: 9, onChanged: (v) => settings.update(scale: v)),
              ]))),
            _section('حریم خصوصی'),
            Card(child: Column(children: [
              SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined, color: scheme.primary),
                title: const Text('نمایش متن پیام در اعلان'),
                value: settings.notifyPreview,
                onChanged: (v) => settings.update(notifyPreview: v)),
              SwitchListTile(
                secondary: Icon(Icons.visibility_off_outlined, color: scheme.primary),
                title: const Text('مخفی کردن متن پیام در فهرست و مبالغ'),
                value: settings.hidePreview,
                onChanged: (v) => settings.update(hidePreview: v)),
            ])),
            _section('امکانات'),
            Card(child: Column(children: [
              ListTile(
                leading: Icon(Icons.bolt_rounded, color: scheme.primary),
                title: const Text('پیام‌های آماده'),
                subtitle: Text('${Jalali.digits(store.templates.length)} پیام برای ارسال سریع'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: _templates),
              ListTile(
                leading: Icon(Icons.done_all_rounded, color: scheme.primary),
                title: const Text('خواندن همه پیام‌ها'),
                onTap: store.markAllRead),
            ])),
            _section('درباره'),
            Card(child: Column(children: [
              ListTile(
                leading: Icon(Icons.system_update_outlined, color: scheme.primary),
                title: const Text('بررسی به‌روزرسانی'),
                trailing: checking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_left_rounded),
                onTap: checking ? null : _checkUpdate),
              ListTile(
                leading: Icon(Icons.language_rounded, color: scheme.primary),
                title: const Text('وب‌سایت پیامیار'),
                subtitle: const Text('honarmardomi.ir/payamyar'),
                onTap: () => UpdateService.openDownload('https://honarmardomi.ir/payamyar/')),
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('پیامیار نسخه ۱٫۰'),
                subtitle: Text('از خانواده هنر مردمی • پیام‌های شما فقط روی گوشی خودتان است')),
            ])),
          ]),
        );
      },
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
    child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
  );
}
