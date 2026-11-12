import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../brand_mark.dart';
import '../chat_theme.dart';
import '../jalali.dart';
import '../sms_bridge.dart';
import '../templates.dart';
import 'compose_screen.dart';
import 'compose_tools.dart';
import 'home_screen.dart';
import 'notification_style_screen.dart';
import 'support_pages.dart';

/// Settings hub: a short, friendly list of sections; each opens its own page.
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
      if (!store.updateCheckFailed) store.onNotice?.call('شما آخرین نسخه پیامیار را دارید.');
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

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, settings]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final delay = settings.sendDelayEnabled ? '${Jalali.digits(settings.sendDelaySeconds)} ثانیه فرصت لغو' : 'ارسال فوری';
        const feedback = {SentFeedback.sound: 'صدای کوتاه ارسال', SentFeedback.notification: 'اعلان', SentFeedback.silent: 'بی‌صدا'};
        return Scaffold(
          appBar: AppBar(title: const Text('تنظیمات')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            _HeaderCard(packageInfo: packageInfo, store: store, checking: checking, onCheck: _checkUpdate),
            const SizedBox(height: 14),
            SettingsGroup(children: [
              SettingsTile(icon: Icons.send_rounded, color: const Color(0xFF087F81),
                title: 'پیامک و ارسال', subtitle: '$delay • ${feedback[settings.sentFeedback]}',
                onTap: () => _open(SendingSettingsPage(store: store, settings: settings))),
              SettingsTile(icon: Icons.palette_outlined, color: const Color(0xFF75539A),
                title: 'ظاهر و قالب گفتگو', subtitle: 'قالب ${chatStyleNames[settings.chatStyle]} • رنگ، قلم و اندازه متن',
                onTap: () => _open(AppearanceSettingsPage(settings: settings))),
              SettingsTile(icon: Icons.notifications_none_rounded, color: const Color(0xFFC0583B),
                title: 'اعلان‌ها و صدا', subtitle: settings.quietHours ? 'ساعت سکوت فعال است' : 'اعلان پیام، صدا و ساعت سکوت',
                onTap: () => _open(NotificationSettingsPage(settings: settings))),
              SettingsTile(icon: Icons.shield_outlined, color: const Color(0xFF305F91),
                title: 'حریم خصوصی و امنیت', subtitle: 'مخفی‌سازی متن، مسدودها و دسترسی‌ها',
                onTap: () => _open(PrivacySettingsPage(store: store, settings: settings))),
            ]),
            const SizedBox(height: 12),
            SettingsGroup(children: [
              SettingsTile(icon: Icons.bolt_rounded, color: const Color(0xFFA17A37),
                title: 'پیام‌های آماده',
                subtitle: '${Jalali.digits(builtInTemplates.values.fold<int>(0, (n, l) => n + l.length))} پیام آماده و ${Jalali.digits(store.templates.length)} پیام شما',
                onTap: () async {
                  final text = await showTemplatesSheet(context, store);
                  if (text != null && context.mounted) _open(ComposeScreen(store: store, initialBody: text));
                }),
              SettingsTile(icon: Icons.done_all_rounded, color: const Color(0xFF47765F),
                title: 'خواندن همه پیام‌ها', subtitle: 'علامت‌گذاری همه گفتگوها به‌عنوان خوانده‌شده',
                onTap: store.markAllRead),
              SettingsTile(icon: Icons.backup_outlined, color: const Color(0xFF3A7CA5),
                title: 'پشتیبان تنظیمات', subtitle: 'انتقال تنظیمات، امضا و پیام‌های آماده به گوشی دیگر',
                onTap: () => _open(BackupPage(store: store, settings: settings))),
            ]),
            const SizedBox(height: 12),
            SettingsGroup(children: [
              SettingsTile(icon: Icons.help_outline_rounded, color: scheme.primary,
                title: 'سوالات متداول', onTap: () => _open(const FaqPage())),
              SettingsTile(icon: Icons.bug_report_outlined, color: scheme.primary,
                title: 'گزارش خرابی', onTap: () => _open(BugReportPage(store: store, settings: settings))),
              SettingsTile(icon: Icons.chat_outlined, color: scheme.primary,
                title: 'ارتباط با ما', onTap: () => _open(const ContactPage())),
              SettingsTile(icon: Icons.info_outline_rounded, color: scheme.primary,
                title: 'درباره پیامیار', onTap: () => _open(AboutPage(packageInfo: packageInfo))),
            ]),
          ]),
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Future<PackageInfo> packageInfo;
  final AppStore store;
  final bool checking;
  final VoidCallback onCheck;
  const _HeaderCard({required this.packageInfo, required this.store, required this.checking, required this.onCheck});
  @override
  Widget build(BuildContext context) {
    final busy = checking || store.updateProgress != null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [Color(0xFF0B6C70), Color(0xFF12444C), Color(0xFF17353B)])),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PayamYarLogotype(height: 48, tagline: true, color: Colors.white),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: FutureBuilder<PackageInfo>(
            future: packageInfo,
            builder: (context, snap) => Text(
              snap.hasData ? 'نسخه ${Jalali.digits(snap.data!.version)} • اندروید' : 'در حال خواندن نسخه…',
              style: const TextStyle(color: Color(0xFFD8E9E6), fontSize: 12.5)))),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40),
              backgroundColor: const Color(0xFFFFD27A), foregroundColor: const Color(0xFF3A2A05)),
            onPressed: busy ? null : onCheck,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_rounded, size: 18),
            label: Text(store.updateProgress != null
                ? '${Jalali.digits(((store.updateProgress ?? 0) * 100).round())}٪'
                : 'بررسی نسخه جدید')),
        ]),
      ]),
    );
  }
}

/// Rounded card that groups related tiles with hairline dividers.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  const SettingsGroup({super.key, required this.children, this.title});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null)
        Padding(padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Text(title!, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700))),
      Card(child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 64, endIndent: 16, color: scheme.outlineVariant.withValues(alpha: .5)),
          children[i],
        ],
      ])),
    ]);
  }
}

/// List row with a coloured rounded icon, like a native settings app.
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const SettingsTile({super.key, required this.icon, required this.color, required this.title,
    this.subtitle, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    leading: Container(width: 38, height: 38,
      decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 21)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_left_rounded)),
    onTap: onTap,
  );
}

class _Page extends StatelessWidget {
  final String title;
  final Listenable listenable;
  final List<Widget> Function(BuildContext) children;
  const _Page({required this.title, required this.listenable, required this.children});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListenableBuilder(listenable: listenable,
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: children(context))),
  );
}

// ───────────── sending ─────────────

class SendingSettingsPage extends StatelessWidget {
  final AppStore store;
  final AppSettings settings;
  const SendingSettingsPage({super.key, required this.store, required this.settings});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'پیامک و ارسال',
    listenable: Listenable.merge([store, settings]),
    children: (context) {
      final scheme = Theme.of(context).colorScheme;
      return [
        if (SmsBridge.supported)
          SettingsGroup(title: 'پیام‌رسان', children: [
            SettingsTile(icon: store.isDefault ? Icons.verified_rounded : Icons.sms_outlined,
              color: store.isDefault ? Colors.green : scheme.primary,
              title: 'پیام‌رسان پیش‌فرض',
              subtitle: store.isDefault ? 'پیامیار پیام‌رسان پیش‌فرض گوشی است' : 'برای دریافت پیام‌های جدید فعال کنید',
              onTap: store.isDefault ? null : store.requestDefault),
            if (store.sims.length > 2)
              SettingsTile(icon: Icons.sim_card_outlined, color: scheme.primary, title: 'سیم‌کارت ارسال',
                subtitle: store.sims.firstWhere((s) => s['id'] == store.selectedSim,
                  orElse: () => store.sims.first)['label'].toString(),
                onTap: () => showModalBottomSheet<void>(context: context, showDragHandle: true,
                  builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final sim in store.sims)
                      ListTile(
                        leading: Icon(store.selectedSim == sim['id'] ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: scheme.primary),
                        title: Text(sim['label'].toString()),
                        onTap: () { store.selectSim(sim['id'] as int); Navigator.pop(ctx); }),
                  ])))),
          ]),
        SettingsGroup(title: 'تأخیر در ارسال (فرصت لغو)', children: [
          SwitchListTile(
            secondary: Icon(Icons.timer_outlined, color: scheme.primary),
            title: const Text('فرصت لغو پیش از ارسال'),
            subtitle: const Text('دور دکمه ارسال حلقه‌ای می‌چرخد؛ تا پایان آن با لمس ✕ پیام لغو می‌شود.'),
            value: settings.sendDelayEnabled,
            onChanged: (v) => settings.update(sendDelayEnabled: v)),
          if (settings.sendDelayEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مدت تأخیر: ${Jalali.digits(settings.sendDelaySeconds)} ثانیه',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                Slider(value: settings.sendDelaySeconds.toDouble(), min: 1, max: 10, divisions: 9,
                  label: '${Jalali.digits(settings.sendDelaySeconds)} ثانیه',
                  onChanged: (v) => settings.update(sendDelaySeconds: v.round())),
                Wrap(spacing: 8, children: [
                  for (final s in const [2, 3, 5, 8])
                    ChoiceChip(label: Text('${Jalali.digits(s)} ثانیه'), selected: settings.sendDelaySeconds == s,
                      onSelected: (_) => settings.update(sendDelaySeconds: s)),
                ]),
              ]),
            ),
        ]),
        SettingsGroup(title: 'تأیید ارسال', children: [
          for (final f in SentFeedback.values)
            ListTile(
              leading: Icon(settings.sentFeedback == f ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: scheme.primary),
              onTap: () => settings.update(sentFeedback: f),
              title: Text(const {SentFeedback.sound: 'فقط صدای کوتاه ارسال',
                SentFeedback.notification: 'اعلان «پیامک ارسال شد»', SentFeedback.silent: 'بدون صدا و اعلان'}[f]!),
              subtitle: Text(const {SentFeedback.sound: 'مثل پیام‌رسان‌ها؛ وقتی شبکه پیام را پذیرفت یک صدای ملایم پخش می‌شود',
                SentFeedback.notification: 'کارت اعلان در نوار وضعیت', SentFeedback.silent: 'وضعیت فقط داخل گفتگو دیده می‌شود'}[f]!),
            ),
          if (SmsBridge.supported && settings.sentFeedback == SentFeedback.sound)
            ListTile(leading: Icon(Icons.play_circle_outline_rounded, color: scheme.primary),
              title: const Text('شنیدن صدای ارسال'), onTap: SmsBridge.previewSentSound),
        ]),
        SettingsGroup(title: 'نوشتن پیام', children: [
          SwitchListTile(
            secondary: Icon(Icons.keyboard_return_rounded, color: scheme.primary),
            title: const Text('ارسال با کلید Enter'),
            subtitle: const Text('خاموش: Enter به خط بعد می‌رود'),
            value: settings.enterToSend, onChanged: (v) => settings.update(enterToSend: v)),
          SwitchListTile(
            secondary: Icon(Icons.auto_awesome_outlined, color: scheme.primary),
            title: const Text('پیشنهاد پاسخ سریع'),
            subtitle: const Text('پاسخ‌های کوتاه پیشنهادی زیر پیام دریافتی'),
            value: settings.smartReplies, onChanged: (v) => settings.update(smartReplies: v)),
          SwitchListTile(
            secondary: Icon(Icons.draw_outlined, color: scheme.primary),
            title: const Text('امضای خودکار'),
            subtitle: Text(settings.signature.isEmpty ? 'متن امضا را وارد کنید' : settings.signature, maxLines: 1,
              overflow: TextOverflow.ellipsis),
            value: settings.signatureEnabled && settings.signature.isNotEmpty,
            onChanged: (v) async {
              if (v && settings.signature.isEmpty) {
                final text = await _askSignature(context, settings.signature);
                if (text == null || text.isEmpty) return;
                await settings.update(signature: text, signatureEnabled: true);
              } else {
                await settings.update(signatureEnabled: v);
              }
            }),
          ListTile(leading: Icon(Icons.edit_outlined, color: scheme.primary), title: const Text('ویرایش متن امضا'),
            onTap: () async {
              final text = await _askSignature(context, settings.signature);
              if (text != null) await settings.update(signature: text);
            }),
        ]),
      ];
    },
  );

  static Future<String?> _askSignature(BuildContext context, String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('امضای پیام'),
      content: TextField(controller: c, maxLength: 60, autofocus: true,
        decoration: const InputDecoration(hintText: 'مثلاً: با احترام، علی')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), child: const Text('ذخیره')),
      ]));
  }
}

// ───────────── appearance ─────────────

class AppearanceSettingsPage extends StatelessWidget {
  final AppSettings settings;
  const AppearanceSettingsPage({super.key, required this.settings});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'ظاهر و قالب گفتگو',
    listenable: settings,
    children: (context) => [
      SettingsGroup(title: 'قالب صفحه گفتگو', children: [
        Padding(padding: const EdgeInsets.all(12), child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final style in ChatStyle.values)
              Padding(padding: const EdgeInsetsDirectional.only(end: 10),
                child: ChatStylePreview(style: style, selected: settings.chatStyle == style,
                  onTap: () => settings.update(chatStyle: style))),
          ]))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('اندازه متن حباب‌ها: ${Jalali.digits(settings.bubbleText.round())}'),
            Slider(value: settings.bubbleText, min: 13, max: 20, divisions: 14,
              onChanged: (v) => settings.update(bubbleText: v)),
          ])),
      ]),
      SettingsGroup(title: 'شخصی‌سازی ظاهر و فونت', children: [
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          SizedBox(width: double.infinity, child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('وزیرمتن')),
              ButtonSegment(value: 1, label: Text('قلم گوشی')),
              ButtonSegment(value: 2, label: Text('نسخ')),
            ],
            selected: {settings.fontChoice},
            onSelectionChanged: (value) => settings.update(fontChoice: value.first))),
          const SizedBox(height: 16),
          Text('اندازه متن برنامه: ${Jalali.digits((settings.scale * 100).round())}٪'),
          Slider(value: settings.scale, min: .9, max: 1.5, divisions: 12, onChanged: (v) => settings.update(scale: v)),
        ])),
      ]),
    ],
  );
}

// ───────────── notifications ─────────────

class NotificationSettingsPage extends StatelessWidget {
  final AppSettings settings;
  const NotificationSettingsPage({super.key, required this.settings});

  String _fmt(int minutes) => Jalali.digits('${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}');

  Future<int?> _pick(BuildContext context, int minutes) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      cancelText: 'انصراف', confirmText: 'تأیید');
    return t == null ? null : t.hour * 60 + t.minute;
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'اعلان‌ها و صدا',
    listenable: settings,
    children: (context) {
      final scheme = Theme.of(context).colorScheme;
      return [
        SettingsGroup(title: 'پیام‌های دریافتی', children: [
          SwitchListTile(
            secondary: Icon(Icons.mark_chat_unread_outlined, color: scheme.primary),
            title: const Text('اعلان دریافت پیامک'),
            value: settings.notifyIncoming, onChanged: (v) => settings.update(notifyIncoming: v)),
          SwitchListTile(
            secondary: Icon(Icons.short_text_rounded, color: scheme.primary),
            title: const Text('نمایش متن پیام در اعلان'),
            value: settings.notifyPreview, onChanged: (v) => settings.update(notifyPreview: v)),
          ListTile(leading: Icon(Icons.music_note_outlined, color: scheme.primary),
            title: const Text('صدا و لرزش پیام دریافتی'), subtitle: const Text('انتخاب آهنگ دلخواه در تنظیمات اندروید'),
            trailing: const Icon(Icons.chevron_left_rounded), onTap: () => SmsBridge.openNotificationChannel('incoming')),
          ListTile(leading: Icon(Icons.auto_awesome_outlined, color: scheme.primary),
            title: const Text('ظاهر اعلان، حباب و پاسخ سریع'),
            subtitle: const Text('شیشه‌ای، رنگ، حباب گفتگو و پاسخ‌های آماده'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => NotificationStyleScreen(settings: settings)))),
        ]),
        SettingsGroup(title: 'ساعت سکوت', children: [
          SwitchListTile(
            secondary: Icon(Icons.bedtime_outlined, color: scheme.primary),
            title: const Text('بی‌صدا در ساعات استراحت'),
            subtitle: Text('${_fmt(settings.quietStart)} تا ${_fmt(settings.quietEnd)} — اعلان‌ها بی‌صدا نمایش داده می‌شوند'),
            value: settings.quietHours, onChanged: (v) => settings.update(quietHours: v)),
          if (settings.quietHours) ...[
            ListTile(leading: const Icon(Icons.nights_stay_outlined), title: const Text('شروع'),
              trailing: Text(_fmt(settings.quietStart)),
              onTap: () async { final m = await _pick(context, settings.quietStart); if (m != null) settings.update(quietStart: m); }),
            ListTile(leading: const Icon(Icons.wb_sunny_outlined), title: const Text('پایان'),
              trailing: Text(_fmt(settings.quietEnd)),
              onTap: () async { final m = await _pick(context, settings.quietEnd); if (m != null) settings.update(quietEnd: m); }),
          ],
        ]),
        SettingsGroup(title: 'دسترسی اعلان', children: [
          ListTile(leading: Icon(Icons.settings_applications_outlined, color: scheme.primary),
            title: const Text('تنظیمات اعلان اندروید'), trailing: const Icon(Icons.chevron_left_rounded),
            onTap: SmsBridge.openNotificationSettings),
        ]),
      ];
    },
  );
}

// ───────────── privacy ─────────────

class PrivacySettingsPage extends StatelessWidget {
  final AppStore store;
  final AppSettings settings;
  const PrivacySettingsPage({super.key, required this.store, required this.settings});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'حریم خصوصی و امنیت',
    listenable: Listenable.merge([store, settings]),
    children: (context) {
      final scheme = Theme.of(context).colorScheme;
      return [
        SettingsGroup(title: 'نمایش', children: [
          SwitchListTile(
            secondary: Icon(Icons.visibility_off_outlined, color: scheme.primary),
            title: const Text('مخفی کردن متن پیام در فهرست و مبالغ'),
            value: settings.hidePreview, onChanged: (v) => settings.update(hidePreview: v)),
        ]),
        if (SmsBridge.supported)
          SettingsGroup(title: 'دسترسی‌ها', children: [
            SettingsTile(icon: Icons.lock_open_rounded, color: scheme.primary, title: 'دسترسی‌های برنامه',
              subtitle: store.permissions.contacts ? 'پیامک، مخاطبان و اعلان' : 'دسترسی مخاطبان داده نشده؛ نام‌ها نمایش داده نمی‌شوند',
              onTap: () async {
                final state = await store.requestPermissions();
                if (state.canRead && state.contacts) {
                  store.onNotice?.call('همه دسترسی‌ها فعال است.');
                } else {
                  await SmsBridge.openAppSettings();
                }
              }),
            SettingsTile(icon: Icons.bolt_rounded, color: store.access.complete ? Colors.green : scheme.primary,
              title: 'دسترسی‌های ویژه',
              subtitle: store.access.complete ? 'اعلان، باتری و زمان‌بندی دقیق فعال است' : 'برای دریافت مطمئن پیام‌ها در پس‌زمینه کامل کنید',
              onTap: () => showSpecialAccessSheet(context, store)),
            SettingsTile(icon: Icons.block_rounded, color: scheme.error, title: 'شماره‌های مسدود',
              onTap: SmsBridge.manageBlocked),
          ]),
        const Padding(padding: EdgeInsets.all(12), child: Text(
          'پیامیار متن پیامک‌ها و مخاطبان شما را به هیچ سروری ارسال نمی‌کند. تنها ارتباط اینترنتی برنامه، بررسی نسخه جدید از honarmardomi.ir است.',
          style: TextStyle(fontSize: 12.5, height: 1.8))),
      ];
    },
  );
}

// ───────────── backup ─────────────

class BackupPage extends StatelessWidget {
  final AppStore store;
  final AppSettings settings;
  const BackupPage({super.key, required this.store, required this.settings});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'پشتیبان تنظیمات',
    listenable: settings,
    children: (context) {
      final scheme = Theme.of(context).colorScheme;
      return [
        const Padding(padding: EdgeInsets.fromLTRB(8, 12, 8, 4), child: Text(
          'پشتیبان شامل تنظیمات، امضا و پیام‌های آماده شماست؛ متن پیامک‌ها و مخاطبان در آن نیست. '
          'پیش از حذف برنامه یا تعویض گوشی آن را برای خودتان بفرستید و بعد با «بازیابی» برگردانید.',
          style: TextStyle(height: 1.8))),
        SettingsGroup(children: [
          SettingsTile(icon: Icons.ios_share_rounded, color: scheme.primary, title: 'ارسال پشتیبان',
            subtitle: 'از طریق پیام‌رسان یا ایمیل برای خودتان',
            onTap: () async {
              final text = store.exportBackup(settings);
              final shared = await SmsBridge.shareText(text, subject: 'پشتیبان پیامیار', title: 'ارسال پشتیبان');
              if (!shared) {
                await Clipboard.setData(ClipboardData(text: text));
                store.onNotice?.call('پشتیبان در حافظه موقت کپی شد.');
              }
            }),
          SettingsTile(icon: Icons.settings_backup_restore_rounded, color: scheme.primary, title: 'بازیابی از متن کپی‌شده',
            subtitle: 'ابتدا متن پشتیبان را کپی کنید',
            onTap: () async {
              final data = await Clipboard.getData('text/plain');
              final ok = await store.importBackup(data?.text ?? '', settings);
              store.onNotice?.call(ok ? 'تنظیمات بازیابی شد.' : 'متن کپی‌شده پشتیبان معتبر پیامیار نیست.');
            }),
        ]),
      ];
    },
  );
}
