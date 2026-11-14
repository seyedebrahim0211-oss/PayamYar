import 'dart:async';
import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../jalali.dart';
import '../notify_banner.dart';
import '../sms_bridge.dart';
import 'glass_banner.dart';
import 'settings_screen.dart' show SettingsGroup;

/// Full personalisation of incoming-message alerts: the in-app glass banner, the Android
/// notification (glass avatar, heads-up alerts) and the ready-made quick replies.
class NotificationStyleScreen extends StatefulWidget {
  final AppSettings settings;
  const NotificationStyleScreen({super.key, required this.settings});

  @override
  State<NotificationStyleScreen> createState() => _NotificationStyleScreenState();
}

class _NotificationStyleScreenState extends State<NotificationStyleScreen> {
  Timer? _previewTimer;
  String? _activePreview;

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  void _previewTimerStart(String mode) {
    _previewTimer?.cancel();
    setState(() => _activePreview = mode);
    _previewTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _activePreview = null);
    });
  }

  void _testInApp() {
    _previewTimerStart('flutter');
    currentBanner.value = IncomingBanner.preview();
  }

  Future<void> _testAndroid() async {
    if (currentBanner.value?.sample == true) currentBanner.value = null;
    _previewTimerStart('android');
    try {
      final visible = await SmsBridge.previewNotification();
      if (!visible && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اعلان واقعی مجاز نیست؛ دریافت پیام و مجوز اعلان اندروید را در تنظیمات فعال کنید.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اعلان واقعی نمایش داده نشد. مجوز اعلان و تنظیمات گوشی را بررسی کنید.'),
        ));
      }
    }
  }

  Future<void> _addReply(BuildContext context) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پاسخ آماده جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'مثلاً: در جلسه هستم'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('افزودن')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    await widget.settings.updateNotify(quickReplies: [...widget.settings.quickReplies, text]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ظاهر اعلان و پاسخ سریع')),
        body: ListenableBuilder(
          listenable: widget.settings,
          builder: (context, child) {
            final scheme = Theme.of(context).colorScheme;
            final s = widget.settings;
            final seconds = Jalali.digits(s.bannerSeconds);
            final blur = Jalali.digits(s.bannerBlur.round());
            final opacity = Jalali.digits((s.bannerOpacity * 100).round());
            return Column(children: [
              // Always-visible live preview while settings scroll beneath it.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(height: 170, width: double.infinity,
                  child: _activePreview == null
                      ? _PreviewStage(settings: s)
                      : Center(child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            _activePreview == 'android'
                                ? 'در حال آزمایش اعلان واقعی اندروید. پنجره بالای گوشی را ببینید و برای خواندن متن کامل، اعلان را باز کنید.'
                                : 'پیش‌نمایش شیشه‌ای داخل برنامه در بالای صفحه نمایش داده می‌شود.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ))),
              ),
              Expanded(child: ListView(
              key: const PageStorageKey('notification_settings_scroll'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
                  onPressed: _testInApp,
                  icon: const Icon(Icons.web_asset_rounded),
                  label: const Text('پیش‌نمایش اعلان شیشه‌ای یکپارچه'),
                )),
                const SizedBox(height: 8),
                if (SmsBridge.supported)
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: _testAndroid,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('آزمایش اعلان واقعی اندروید'),
                  )),
                const SizedBox(height: 16),
                SettingsGroup(title: 'اعلان شیشه‌ای یکپارچه', children: [
                  SwitchListTile(
                    secondary: Icon(Icons.web_asset_rounded, color: scheme.primary),
                    title: const Text('نمایش بنر هنگام باز بودن پیامیار'),
                    subtitle: const Text('داخل برنامه کارت متحرک Flutter؛ بیرون برنامه اعلان بومی اندروید با رنگ هماهنگ، در محدوده ارتفاع مجاز گوشی.'),
                    value: s.notifyInApp,
                    onChanged: (v) => s.updateNotify(notifyInApp: v),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SegmentedButton<BannerStyle>(
                      showSelectedIcon: false,
                      segments: [
                        for (final style in BannerStyle.values)
                          ButtonSegment(value: style, label: Text(bannerStyleNames[style]!)),
                      ],
                      selected: {s.bannerStyle},
                      onSelectionChanged: (v) => s.updateNotify(bannerStyle: v.first),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(spacing: 10, runSpacing: 10, children: [
                      for (var i = 0; i < palettes.length; i++)
                        _ColorDot(
                          color: palettes[i],
                          selected: s.bannerTint == i,
                          onTap: () => s.updateNotify(bannerTint: i),
                        ),
                    ]),
                  ),
                  if (s.bannerStyle == BannerStyle.glass) ...[
                    ListTile(
                      leading: Icon(Icons.blur_on_rounded, color: scheme.primary),
                      title: const Text('میزان مات‌شدن پس‌زمینه'),
                      trailing: Text(blur),
                    ),
                    Slider(
                      value: s.bannerBlur,
                      max: 30,
                      divisions: 30,
                      onChanged: (v) => s.updateNotify(bannerBlur: v),
                    ),
                    ListTile(
                      leading: Icon(Icons.opacity_rounded, color: scheme.primary),
                      title: const Text('شفافیت شیشه'),
                      trailing: Text('$opacity٪'),
                    ),
                    Slider(
                      value: s.bannerOpacity,
                      min: .15,
                      max: .95,
                      divisions: 16,
                      onChanged: (v) => s.updateNotify(bannerOpacity: v),
                    ),
                  ],
                  SwitchListTile(
                    secondary: Icon(Icons.crop_16_9_outlined, color: scheme.primary),
                    title: const Text('کارت شیشه‌ای جمع‌وجور'),
                    subtitle: const Text('کارت داخل برنامه را کوتاه می‌کند؛ در اعلان اندروید پیام طولانی با بازکردن کشوی اعلان خوانده می‌شود.'),
                    value: s.bannerCompact,
                    onChanged: (v) => s.updateNotify(bannerCompact: v),
                  ),
                  ListTile(
                    leading: Icon(Icons.width_normal_outlined, color: scheme.primary),
                    title: const Text('عرض کارت داخلی'),
                    subtitle: const Text('عرض کارت داخل برنامه؛ عرض اعلان اندروید در اختیار سیستم‌عامل است'),
                    trailing: Text(Jalali.digits(s.bannerMaxWidth.round())),
                  ),
                  Slider(
                    value: s.bannerMaxWidth, min: 280, max: 520, divisions: 12,
                    onChanged: (v) => s.updateNotify(bannerMaxWidth: v),
                  ),
                  SwitchListTile(
                    secondary: Icon(Icons.bubble_chart_outlined, color: scheme.primary),
                    title: const Text('حباب‌های متحرک'),
                    subtitle: const Text('حباب‌های شیشه‌ای ملایم پشت متن'),
                    value: s.bannerBubbles,
                    onChanged: (v) => s.updateNotify(bannerBubbles: v),
                  ),
                  ListTile(
                    leading: Icon(Icons.vertical_align_center_rounded, color: scheme.primary),
                    title: const Text('محل نمایش'),
                    trailing: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: true, label: Text('بالا')),
                        ButtonSegment(value: false, label: Text('پایین')),
                      ],
                      selected: {s.bannerTop},
                      onSelectionChanged: (v) => s.updateNotify(bannerTop: v.first),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.timer_outlined, color: scheme.primary),
                    title: const Text('مدت نمایش'),
                    trailing: Text('$seconds ثانیه'),
                  ),
                  Slider(
                    value: s.bannerSeconds.toDouble(),
                    min: 2,
                    max: 15,
                    divisions: 13,
                    onChanged: (v) => s.updateNotify(bannerSeconds: v.round()),
                  ),
                ]),
                SettingsGroup(title: 'اعلان اندروید', children: [
                  SwitchListTile(
                    secondary: Icon(Icons.visibility_outlined, color: scheme.primary),
                    title: const Text('نمایش متن پیام در اعلان واقعی'),
                    subtitle: const Text('برای دیدن پیام کامل در اعلان اندروید فعال کنید؛ در حالت خاموش، متن برای حفظ حریم خصوصی مخفی می‌ماند.'),
                    value: s.notifyPreview,
                    onChanged: (v) => s.update(notifyPreview: v),
                  ),
                  SwitchListTile(
                    secondary: Icon(Icons.auto_awesome_outlined, color: scheme.primary),
                    title: const Text('تصویر شیشه‌ای فرستنده'),
                    subtitle: const Text('درخشش، حلقه رنگی و حباب روی عکس مخاطب'),
                    value: s.notifyGlassAvatar,
                    onChanged: (v) => s.updateNotify(notifyGlassAvatar: v),
                  ),
                  ListTile(
                    leading: Icon(Icons.crop_square_rounded, color: scheme.primary),
                    title: const Text('شکل تصویر'),
                    trailing: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('دایره')),
                        ButtonSegment(value: 1, label: Text('چهارگوش نرم')),
                      ],
                      selected: {s.notifyAvatarShape},
                      onSelectionChanged: (v) => s.updateNotify(notifyAvatarShape: v.first),
                    ),
                  ),
                  const ListTile(
                    leading: Icon(Icons.web_asset_rounded),
                    title: Text('اعلان شیشه‌ای بالای صفحه'),
                    subtitle: Text('ظاهر بومی به رنگ و سبک انتخابی نزدیک شده؛ مات‌سازی زنده و حباب متحرک فقط داخل برنامه امکان‌پذیر است. ارتفاع اعلان واقعی با Android/MagicOS کنترل می‌شود.'),
                  ),
                  SwitchListTile(
                    secondary: Icon(Icons.pin_outlined, color: scheme.primary),
                    title: const Text('دکمه کپی کد تأیید'),
                    value: s.notifyOtpCopy,
                    onChanged: (v) => s.updateNotify(notifyOtpCopy: v),
                  ),
                ]),
                SettingsGroup(title: 'پاسخ سریع', children: [
                  SwitchListTile(
                    secondary: Icon(Icons.quickreply_outlined, color: scheme.primary),
                    title: const Text('پاسخ از داخل اعلان'),
                    subtitle: const Text('نوشتن پاسخ یا انتخاب پاسخ آماده بدون باز کردن برنامه'),
                    value: s.notifyQuickReply,
                    onChanged: (v) => s.updateNotify(notifyQuickReply: v),
                  ),
                  if (s.notifyQuickReply)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final r in s.quickReplies)
                          InputChip(
                            label: Text(r),
                            onDeleted: () => s.updateNotify(
                                quickReplies: [for (final x in s.quickReplies) if (x != r) x]),
                          ),
                        if (s.quickReplies.length < 5)
                          ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('افزودن'),
                            onPressed: () => _addReply(context),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('پیش‌فرض'),
                          onPressed: () => s.updateNotify(quickReplies: defaultQuickReplies),
                        ),
                      ]),
                    ),
                ]),
              ],
              )),
            ]);
          },
        ),
      );
}

/// Colourful backdrop so the frosted glass can actually be seen in the preview.
class _PreviewStage extends StatelessWidget {
  final AppSettings settings;
  const _PreviewStage({required this.settings});

  @override
  Widget build(BuildContext context) {
    final tint = settings.bannerColor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 22, 12, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color.lerp(tint, Colors.white, .55)!, const Color(0xFFF3E3BE), Color.lerp(tint, Colors.white, .2)!],
          ),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          const Positioned(top: -10, left: 20, child: _Blob(color: Color(0xFFDDA54A), size: 70)),
          Positioned(bottom: -14, right: 30, child: _Blob(color: tint, size: 90)),
          const Positioned(top: 30, right: -10, child: _Blob(color: Color(0xFF9F5369), size: 46)),
          Align(
            alignment: settings.bannerTop ? Alignment.topCenter : Alignment.bottomCenter,
            child: GlassBannerCard(banner: IncomingBanner.preview(), settings: settings, interactive: false),
          ),
        ]),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .85)),
      );
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
                color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .4), blurRadius: selected ? 12 : 0)],
          ),
          child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
        ),
      );
}
