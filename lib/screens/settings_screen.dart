import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../brand_mark.dart';
import '../jalali.dart';
import '../sms_bridge.dart';
import '../templates.dart';
import '../update_service.dart';
import 'compose_screen.dart';
import 'compose_tools.dart';
import 'home_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  const SettingsScreen({super.key, required this.store, required this.settings});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool checking = false;
  late final Future<PackageInfo> packageInfo = PackageInfo.fromPlatform();
  AppStore get store => widget.store;
  AppSettings get settings => widget.settings;

  Future<void> _checkUpdate() async {
    setState(() => checking = true);
    final found = await store.checkForUpdate(manual: true);
    if (!mounted) return;
    setState(() => checking = false);
    if (!found) {
      if (!store.updateCheckFailed) {
        store.onNotice?.call('شما آخرین نسخه پیامیار را دارید.');
      }
      return;
    }
    final info = store.update!;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('نسخه جدید ${Jalali.digits(info.version)}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(info.notes.isEmpty ? 'نسخه جدید دریافت و نصب شود؟' : info.notes),
        if (info.sizeLabel.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('حجم دریافت: ${info.sizeLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 6),
        const Text('فایل از honarmardomi.ir دریافت و امضای آن پیش از نصب بررسی می‌شود. داده‌های شما حفظ می‌شود.',
          style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بعداً')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('دریافت و نصب به‌روزرسانی')),
      ]));
    if (ok == true) await store.installUpdate();
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
                  leading: Icon(Icons.bolt_rounded, color: store.access.complete ? Colors.green : scheme.primary),
                  title: const Text('دسترسی‌های ویژه'),
                  subtitle: Text(store.access.complete
                      ? 'اعلان، باتری و زمان‌بندی دقیق فعال است'
                      : 'برای دریافت مطمئن پیام‌ها در پس‌زمینه کامل کنید'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => showSpecialAccessSheet(context, store)),
                ListTile(
                  leading: Icon(Icons.block_rounded, color: scheme.primary),
                  title: const Text('شماره‌های مسدود'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: SmsBridge.manageBlocked),
              ])),
            ],
            _section('شخصی‌سازی ظاهر و فونت'),
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
                const Text('قلم برنامه'),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('وزیرمتن')),
                    ButtonSegment(value: 1, label: Text('قلم گوشی')),
                    ButtonSegment(value: 2, label: Text('نسخ')),
                  ],
                  selected: {settings.fontChoice},
                  onSelectionChanged: (value) => settings.update(fontChoice: value.first)),
                const SizedBox(height: 16),
                Text('اندازه متن: ${Jalali.digits((settings.scale * 100).round())}٪'),
                Slider(value: settings.scale, min: .9, max: 1.5, divisions: 12, onChanged: (v) => settings.update(scale: v)),
                const Text('پیش‌نمایش: پیام فارسی با اندازه و قلم انتخاب‌شده', style: TextStyle(fontSize: 14)),
              ]))),
            _section('اعلان‌های اندروید و صدای پیام'),
            Card(child: Column(children: [
              SwitchListTile(
                secondary: Icon(Icons.mark_chat_unread_outlined, color: scheme.primary),
                title: const Text('اعلان دریافت پیامک'),
                subtitle: const Text('نمایش پیام جدید روی گوشی'),
                value: settings.notifyIncoming,
                onChanged: (value) => settings.update(notifyIncoming: value)),
              SwitchListTile(
                secondary: Icon(Icons.outgoing_mail, color: scheme.primary),
                title: const Text('اعلان و صدای تأیید ارسال'),
                subtitle: const Text('فقط وقتی شبکه پذیرش یا تحویل را تأیید کند'),
                value: settings.notifySent,
                onChanged: (value) => settings.update(notifySent: value)),
              ListTile(
                leading: Icon(Icons.music_note_outlined, color: scheme.primary),
                title: const Text('صدای شخصی دریافت پیام'),
                subtitle: const Text('انتخاب صدای پیش‌فرض یا دلخواه از تنظیمات اندروید'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => SmsBridge.openNotificationChannel('incoming')),
              ListTile(
                leading: Icon(Icons.notifications_active_outlined, color: scheme.primary),
                title: const Text('صدای تأیید ارسال'),
                subtitle: const Text('انتخاب صدا و ویبره در گوشی'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => SmsBridge.openNotificationChannel('sent')),
            ])),
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
                subtitle: Text('${Jalali.digits(builtInTemplates.values.fold<int>(0, (n, l) => n + l.length))} پیام آماده و ${Jalali.digits(store.templates.length)} پیام شما'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () async {
                  final text = await showTemplatesSheet(context, store);
                  if (text != null && context.mounted) {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComposeScreen(store: store, initialBody: text)));
                  }
                }),
              ListTile(
                leading: Icon(Icons.done_all_rounded, color: scheme.primary),
                title: const Text('خواندن همه پیام‌ها'),
                onTap: store.markAllRead),
            ])),
            _section('درباره پیامیار'),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topRight, end: Alignment.bottomLeft,
                  colors: [Color(0xFF0B6C70), Color(0xFF12444C), Color(0xFF17353B)],
                ),
              ),
              padding: const EdgeInsets.all(21),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Align(alignment: AlignmentDirectional.centerStart,
                    child: PayamYarLogotype(height: 52, tagline: true, color: Colors.white))),
                ]),
                const SizedBox(height: 18),
                FutureBuilder<PackageInfo>(
                  future: packageInfo,
                  builder: (context, snapshot) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white24)),
                    child: Row(children: [
                      const Icon(Icons.verified_outlined, size: 20, color: Color(0xFFEBD3A2)),
                      const SizedBox(width: 10),
                      Text(snapshot.hasData ? 'نسخه ${Jalali.digits(snapshot.data!.version)}'
                        : 'در حال خواندن نسخه…', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      const Text('اندروید', style: TextStyle(color: Color(0xFFD8E9E6), fontSize: 12)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('طراحی و توسعه با الهام از هویت بصری ایرانی. مدیریت پیام‌های گوشی بدون ارسال محتوای پیامک به سایت.',
                  style: TextStyle(color: Color(0xFFE2EFEC), height: 1.75, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 11),
            Card(child: Column(children: [
              ListTile(
                leading: Icon(Icons.system_update_outlined, color: scheme.primary),
                title: const Text('بررسی نسخه جدید'),
                subtitle: store.updateProgress != null
                    ? Text('در حال دریافت… ${Jalali.digits(((store.updateProgress ?? 0) * 100).round())}٪')
                    : const Text('دریافت نسخه امضاشده با اجازه شما'),
                trailing: checking || store.updateProgress != null
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_left_rounded),
                onTap: checking || store.updateProgress != null ? null : _checkUpdate),
              const Divider(indent: 17, endIndent: 17, height: 1),
              ListTile(
                leading: Icon(Icons.language_rounded, color: scheme.primary),
                title: const Text('وب‌سایت هنر مردمی'),
                subtitle: const Text('honarmardomi.ir'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                onTap: () => UpdateService.openDownload('https://honarmardomi.ir/')),
              const Divider(indent: 17, endIndent: 17, height: 1),
              ListTile(
                leading: Icon(Icons.phone_android_rounded, color: scheme.primary),
                title: const Text('صفحه رسمی پیامیار و دانلود'),
                subtitle: const Text('honarmardomi.ir/payamyar/'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                onTap: () => UpdateService.openDownload('https://honarmardomi.ir/payamyar/')),
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
