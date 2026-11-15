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

class _NotificationStyleScreenState extends State<NotificationStyleScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _floating = {};
  bool _enableOnReturn = false;
  bool _floatingBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFloating();
  }

  Future<void> _loadFloating() async {
    try {
      final value = await SmsBridge.floatingStatus();
      if (mounted) setState(() => _floating = value);
    } catch (_) {
      if (mounted) setState(() => _floating = {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumeFloating();
  }

  Future<void> _resumeFloating() async {
    await _loadFloating();
    if (!mounted) return;
    if (_enableOnReturn) {
      _enableOnReturn = false;
      if (_floating['permission'] == true) {
        await _toggleFloating(true);
      } else {
        _floatingNotice('اجازه نمایش روی برنامه‌های دیگر داده نشد؛ اعلان استاندارد فعال می‌ماند.');
      }
    }
  }

  void _floatingNotice(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleFloating(bool enabled) async {
    if (_floatingBusy) return;
    setState(() => _floatingBusy = true);
    try {
      if (enabled && _floating['permission'] != true) {
        _enableOnReturn = true;
        if (!await SmsBridge.requestFloatingPermission()) {
          _enableOnReturn = false;
          _floatingNotice('صفحه اجازه نمایش باز نشد؛ از تنظیمات گوشی اجازه نمایش روی برنامه‌های دیگر را فعال کنید.');
        }
        return;
      }
      final ok = await SmsBridge.enableFloating(enabled);
      if (!ok) _floatingNotice('حباب شروع نشد؛ اجازه نمایش روی برنامه‌ها را بررسی کنید.');
      if (ok && enabled) {
        await widget.settings.updateNotify(notifyBubbles: false, bannerStyle: BannerStyle.glass);
      }
      await _loadFloating();
    } catch (_) {
      _floatingNotice('تغییر حالت اعلان انجام نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _floatingBusy = false);
    }
  }

  Future<void> _floatingSize({
    int? bubble, int? text, int? seconds, double? opacity,
    int? style, int? shape, int? color,
  }) async {
    try {
      await SmsBridge.configureFloating(
        bubbleSize: bubble, textSize: text, bubbleSeconds: seconds,
        bubbleOpacity: opacity, bubbleStyle: style,
        bubbleShape: shape, bubbleColor: color);
      await _loadFloating();
    } catch (_) { _floatingNotice('تنظیم ذخیره نشد.'); }
  }

  Timer? _previewTimer;
  String? _activePreview;

  @override
  void dispose() {
    _previewTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
                SettingsGroup(title: 'حباب کنار صفحه و اعلان شناور', children: [
                  SwitchListTile(
                    title: const Text('حباب و کارت شیشه‌ای مستقل'),
                    subtitle: Text(_floating['enabled'] == true
                        ? 'فعال؛ حباب مخاطب فقط هنگام پیام جدید ظاهر می‌شود و سپس خودکار محو می‌شود.'
                        : 'کارت شناور سفید با گوشه‌های گرد؛ نیازمند اجازه نمایش روی برنامه‌ها'),
                    secondary: Icon(Icons.chat_bubble_outline_rounded, color: scheme.primary),
                    value: _floating['enabled'] == true,
                    onChanged: !SmsBridge.supported || _floatingBusy ? null : _toggleFloating,
                  ),
                  if (_floating['enabled'] == true) ...[
                    ListTile(
                      title: const Text('اندازه حباب'),
                      subtitle: Slider(min: 48, max: 72, divisions: 6,
                        value: ((_floating['bubbleSize'] as num?)?.toDouble() ?? 56).clamp(48, 72).toDouble(),
                        label: Jalali.digits((_floating['bubbleSize'] ?? 56).toString()),
                        onChanged: (v) => setState(() => _floating['bubbleSize'] = v.round()),
                        onChangeEnd: (v) => _floatingSize(bubble: v.round())),
                    ),
                    ListTile(
                      title: const Text('اندازه متن کارت شناور'),
                      subtitle: Slider(min: 12, max: 22, divisions: 10,
                        value: ((_floating['textSize'] as num?)?.toDouble() ?? 15).clamp(12, 22).toDouble(),
                        label: Jalali.digits((_floating['textSize'] ?? 15).toString()),
                        onChanged: (v) => setState(() => _floating['textSize'] = v.round()),
                        onChangeEnd: (v) => _floatingSize(text: v.round())),
                    ),
                    ListTile(
                      title: const Text('مدت نمایش حباب مخاطب'),
                      trailing: Text('${_floating['bubbleSeconds'] ?? 18} ثانیه'),
                      subtitle: Slider(
                        min: 8, max: 60, divisions: 13,
                        value: ((_floating['bubbleSeconds'] as num?)?.toDouble() ?? 18).clamp(8, 60).toDouble(),
                        onChanged: (v) => setState(() => _floating['bubbleSeconds'] = v.round()),
                        onChangeEnd: (v) => _floatingSize(seconds: v.round()),
                      ),
                    ),
                    ListTile(
                      title: const Text('جنس حباب'),
                      trailing: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('شیشه‌ای')),
                          ButtonSegment(value: 1, label: Text('رنگی')),
                        ],
                        selected: {(_floating['bubbleStyle'] as int?) ?? 0},
                        onSelectionChanged: (v) {
                          setState(() => _floating['bubbleStyle'] = v.first);
                          _floatingSize(style: v.first);
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('شکل حباب'),
                      trailing: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('دایره')),
                          ButtonSegment(value: 1, label: Text('گردگوشه')),
                        ],
                        selected: {(_floating['bubbleShape'] as int?) ?? 0},
                        onSelectionChanged: (v) {
                          setState(() => _floating['bubbleShape'] = v.first);
                          _floatingSize(shape: v.first);
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('مات‌بودن حباب'),
                      trailing: Text('${(((_floating['bubbleOpacity'] as num?)?.toDouble() ?? .92) * 100).round()}٪'),
                      subtitle: Slider(
                        min: .78, max: 1, divisions: 11,
                        value: ((_floating['bubbleOpacity'] as num?)?.toDouble() ?? .92).clamp(.78, 1).toDouble(),
                        onChanged: (v) => setState(() => _floating['bubbleOpacity'] = v),
                        onChangeEnd: (v) => _floatingSize(opacity: v),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text('رنگ حباب مخاطب', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Wrap(spacing: 12, runSpacing: 12, children: [
                        for (final color in palettes)
                          _ColorDot(
                            color: color,
                            selected: _floating['bubbleColor'] == color.toARGB32(),
                            onTap: () {
                              setState(() => _floating['bubbleColor'] = color.toARGB32());
                              _floatingSize(color: color.toARGB32());
                            },
                          ),
                      ]),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('حباب مخصوص فرستنده آخرین پیام است و دائمی نمایش داده نمی‌شود. با لمس حباب کارت گفتگو باز می‌شود؛ اگر گوشی شروع سرویس شناور را در پس‌زمینه محدود کند، اعلان عادی اندروید باقی می‌ماند.'),
                    ),
                  ],
                  const ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('بدون حباب تکراری'),
                    subtitle: Text('حباب دوم اندروید غیرفعال است؛ اعلان سیستمی در گوشی‌های محدودکننده پنجره شناور باقی می‌ماند.'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('اجازه اعلان و حباب در گوشی'),
                    onTap: () => SmsBridge.openNotificationSettings(),
                  ),
                ]),
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
                    subtitle: const Text('یک کارت شیشه‌ای یکپارچه در داخل و خارج برنامه؛ در صورت محدودیت اندروید، اعلان سیستمی جایگزین می‌شود.'),
                    value: s.notifyInApp,
                    onChanged: (v) => s.updateNotify(notifyInApp: v),
                  ),
                  const ListTile(
                    leading: Icon(Icons.layers_rounded),
                    title: Text('فقط یک طرح: شیشه‌ای یکپارچه'),
                    subtitle: Text('همه کارت‌های داخل برنامه و شناور از همین طرح استفاده می‌کنند؛ رنگ، کدری، قاب و انیمیشن قابل تغییر است.'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(spacing: 10, runSpacing: 10, children: [
                      for (var i = 0; i < palettes.length; i++)
                        _ColorDot(
                          color: palettes[i],
                          selected: s.bannerHue < 0 && s.bannerTint == i,
                          onTap: () => s.updateNotify(bannerTint: i, bannerHue: -1),
                        ),
                    ]),
                  ),
                  ListTile(
                    leading: Icon(Icons.color_lens_outlined, color: scheme.primary),
                    title: const Text('رنگ دلخواه شیشه'),
                    subtitle: const Text('تغییر زنده رنگِ پیش‌نمایش و اعلان شناور'),
                    trailing: TextButton(onPressed: () => s.updateNotify(bannerHue: -1),
                        child: const Text('رنگ پیش‌فرض')),
                  ),
                  Slider(min: 0, max: 360, divisions: 72,
                    value: s.bannerHue < 0 ? 180 : s.bannerHue,
                    onChanged: (v) => s.updateNotify(bannerHue: v)),
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
                      title: const Text('خوانایی و میزان مات‌بودن شیشه'),
                       subtitle: const Text('پیش‌فرض ۹۰٪ برای خوانایی بهتر است'),
                      trailing: Text('$opacity٪'),
                    ),
                    Slider(
                      value: s.bannerOpacity,
                      min: .78,
                      max: 1,
                      divisions: 11,
                      onChanged: (v) => s.updateNotify(bannerOpacity: v),
                    ),
                    ListTile(
                      leading: Icon(Icons.border_outer_rounded, color: scheme.primary),
                      title: const Text('شدت قاب شیشه‌ای'),
                      trailing: Text('${(s.bannerEdge * 100).round()}٪'),
                    ),
                    Slider(min: .15, max: 1, divisions: 17,
                      value: s.bannerEdge,
                      onChanged: (v) => s.updateNotify(bannerEdge: v)),
                    ListTile(
                      leading: Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                      title: const Text('درخشش نور و شیشه'),
                      trailing: Text('${(s.bannerShine * 100).round()}٪'),
                    ),
                    Slider(min: 0, max: 1, divisions: 20,
                      value: s.bannerShine,
                      onChanged: (v) => s.updateNotify(bannerShine: v)),
                    ListTile(
                      leading: Icon(Icons.rounded_corner_rounded, color: scheme.primary),
                      title: const Text('گردی گوشه‌های کارت'),
                      trailing: Text('${s.bannerCorner.round()}'),
                    ),
                    Slider(min: 16, max: 36, divisions: 20,
                      value: s.bannerCorner,
                      onChanged: (v) => s.updateNotify(bannerCorner: v)),

                  ],
                  const ListTile(
                    leading: Icon(Icons.text_snippet_outlined),
                    title: Text('نمایش متن کامل'),
                    subtitle: Text('متن پیام‌های طولانی در کارت قابل پیمایش است، نه بریده یا محو.'),
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
                    title: Text('نمایش سازگار با گوشی'),
                    subtitle: Text('بدون اجازه شناور، اعلان استاندارد اندروید نمایش داده می‌شود. حباب و کارت شناور روی صفحه قفل پنهان می‌شوند؛ با قفل برنامه، متن و کد تأیید نمایش داده نمی‌شوند.'),
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
