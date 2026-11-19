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

typedef _SenderStyle = ({String key, String title, Color color});

class _NotificationStyleScreenState extends State<NotificationStyleScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _floating = {};
  String? _sourceKey;
  List<_SenderStyle> get _sources => [
    for (final source in _floating['sources'] as List? ?? const [])
      if (source case {'key': String key, 'title': String title, 'color': int color})
        (key: key, title: title, color: Color(color)),
  ];
  _SenderStyle? get _selectedSender => widget.settings.bannerSourceColors
      ? _sources.where((sender) => sender.key == _sourceKey).firstOrNull : null;
  Color _senderColor(_SenderStyle sender) {
    final override = widget.settings.bannerSenderTints[sender.key];
    return override == null ? sender.color : Color(override);
  }
  Future<void> _setSenderColor(_SenderStyle sender, Color? color) {
    final colors = Map.of(widget.settings.bannerSenderTints);
    if (color == null) {
      colors.remove(sender.key);
    } else {
      colors[sender.key] = color.toARGB32();
    }
    return widget.settings.updateNotify(bannerSenderTints: colors);
  }
  IncomingBanner _sample() {
    final sender = _selectedSender;
    return IncomingBanner.preview(sender: sender?.title, sourceColor: sender == null ? null : _senderColor(sender).toARGB32());
  }

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
    currentBanner.value = _sample();
  }

  Future<void> _testAndroid() async {
    if (currentBanner.value?.sample == true) currentBanner.value = null;
    _previewTimerStart('android');
    try {
      final visible = await SmsBridge.previewNotification(source: _selectedSender?.key);
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
            final sender = _selectedSender;
            final selectedColor = sender == null ? s.bannerColor : _senderColor(sender);
            final media = MediaQuery.of(context);
            final pinPreview = media.size.height - media.viewInsets.bottom >= 620 &&
                media.textScaler.scale(14) <= 20;
            final preview = _activePreview == null ? _PreviewStage(settings: s, banner: _sample())
                : Padding(padding: const EdgeInsets.all(18),
                    child: Text(_activePreview == 'android' ? 'اعلان آزمایشی را در گوشی ببینید.' :
                      'کارت آزمایشی روی صفحه باز است.', textAlign: TextAlign.center));
            final controls = ListView(
              key: const PageStorageKey('notification_settings_scroll'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!pinPreview) preview,
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
                  onPressed: _testInApp,
                  icon: const Icon(Icons.web_asset_rounded),
                  label: const Text('آزمایش کارت داخل برنامه'),
                )),
                const SizedBox(height: 8),
                if (SmsBridge.supported)
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: _testAndroid,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('آزمایش اعلان روی گوشی'),
                  )),
                const SizedBox(height: 16),
                _ActionSettings(settings: s),
                SettingsGroup(title: 'حباب کنار صفحه و اعلان شناور', children: [
                  SwitchListTile(
                    title: const Text('حباب و کارت شیشه‌ای مستقل'),
                    subtitle: Text(_floating['enabled'] == true
                        ? 'با دریافت پیام، کارت باز می‌شود. پس از بسته‌شدن، حباب مخاطب برای مدت کوتاهی می‌ماند.'
                        : 'برای دیدن کارت شیشه‌ای روی صفحهٔ اصلی یا برنامه‌های دیگر، اجازهٔ نمایش شناور را فعال کنید.'),
                    secondary: Icon(Icons.chat_bubble_outline_rounded, color: scheme.primary),
                    value: _floating['enabled'] == true,
                    onChanged: !SmsBridge.supported || _floatingBusy ? null : _toggleFloating,
                  ),
                  ExpansionTile(
                    title: const Text('تنظیمات حباب و اندازهٔ متن'),
                    children: [
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
                      subtitle: SegmentedButton<int>(
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
                      subtitle: SegmentedButton<int>(
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
                            selected: ((_floating['bubbleColor'] as int?) ?? 0xff087f81).toUnsigned(32) == color.toARGB32(),
                            onTap: () {
                              setState(() => _floating['bubbleColor'] = color.toARGB32());
                              _floatingSize(color: color.toARGB32());
                            },
                          ),
                      ]),
                    ),
                  ]),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('اجازه اعلان و حباب در گوشی'),
                    onTap: () => SmsBridge.openNotificationSettings(),
                  ),
                ]),
                SettingsGroup(title: 'اعلان شیشه‌ای یکپارچه', children: [
                  SwitchListTile(
                    secondary: Icon(Icons.web_asset_rounded, color: scheme.primary),
                    title: const Text('نمایش بنر هنگام باز بودن پیامیار'),
                    subtitle: const Text('با لمس کارت، گفتگو باز می‌شود. فلش کنار نام فرستنده، متن کامل و گزینه‌ها را نشان می‌دهد.'),
                    value: s.notifyInApp,
                    onChanged: (v) => s.updateNotify(notifyInApp: v),
                  ),
                  SwitchListTile(
                    secondary: Icon(Icons.palette_outlined, color: scheme.primary),
                    title: const Text('رنگ اختصاصی پیام‌رسان'),
                    subtitle: const Text('پیامک‌های دارای شناسهٔ ایتا، بله، تلگرام و واتساپ با رنگ خودشان نمایش داده می‌شوند. برای تغییر رنگ، فرستنده را انتخاب کنید.'),
                    value: s.bannerSourceColors,
                    onChanged: (v) => s.updateNotify(bannerSourceColors: v),
                  ),
                  if (s.bannerSourceColors && _sources.isNotEmpty) ListTile(
                    title: const Text('رنگ کارت برای'),
                    trailing: DropdownButton<String>(
                      value: sender?.key ?? '',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('پیام‌یار')),
                        for (final item in _sources) DropdownMenuItem(value: item.key, child: Text(item.title)),
                      ],
                      onChanged: (key) => setState(() => _sourceKey = key),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(spacing: 10, runSpacing: 10, children: [
                      for (var i = 0; i < palettes.length; i++)
                        _ColorDot(
                          color: palettes[i],
                          selected: selectedColor.toARGB32() == palettes[i].toARGB32(),
                          onTap: () => sender == null ? s.updateNotify(bannerTint: i, bannerHue: -1)
                              : _setSenderColor(sender, palettes[i]),
                        ),
                    ]),
                  ),
                  ListTile(
                    leading: Icon(Icons.color_lens_outlined, color: scheme.primary),
                    title: const Text('رنگ دلخواه شیشه'),
                    subtitle: const Text('تغییر زنده رنگِ پیش‌نمایش و اعلان شناور'),
                    trailing: TextButton(onPressed: () => sender == null ? s.updateNotify(bannerTint: 0, bannerHue: -1) : _setSenderColor(sender, null),
                        child: const Text('رنگ پیش‌فرض')),
                  ),
                  Slider(min: 0, max: 360, divisions: 72,
                    value: sender == null && s.bannerHue >= 0 ? s.bannerHue : HSVColor.fromColor(selectedColor).hue,
                    onChanged: (v) => sender == null ? s.updateNotify(bannerHue: v)
                        : _setSenderColor(sender, HSVColor.fromAHSV(1, v, .75, .57).toColor())),
                  ExpansionTile(
                    title: const Text('جزئیات شیشه و قاب'),
                    children: [
                    ListTile(
                      leading: Icon(Icons.blur_on_rounded, color: scheme.primary),
                      title: const Text('محو کردن زمینه در داخل برنامه'),
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

                  ]),
                  ListTile(
                    leading: Icon(Icons.width_normal_outlined, color: scheme.primary),
                    title: const Text('عرض کارت شیشه‌ای'),
                    subtitle: const Text('در داخل برنامه و روی صفحهٔ گوشی'),
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
                    subtitle: SegmentedButton<bool>(
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
                    subtitle: const Text('یک حاشیهٔ نازک و روشن دور عکس مخاطب'),
                    value: s.notifyGlassAvatar,
                    onChanged: (v) => s.updateNotify(notifyGlassAvatar: v),
                  ),
                  const ListTile(leading: Icon(Icons.portrait_outlined), title: Text('شکل عکس مخاطب')),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(spacing: 8, runSpacing: 4, children: [
                      ChoiceChip(label: const Text('دایره'), selected: s.notifyAvatarShape == 0,
                          onSelected: (_) => s.updateNotify(notifyAvatarShape: 0)),
                      ChoiceChip(label: const Text('چهارگوش نرم'), selected: s.notifyAvatarShape == 1,
                          onSelected: (_) => s.updateNotify(notifyAvatarShape: 1)),
                    ])),
                  const ListTile(
                    leading: Icon(Icons.web_asset_rounded),
                    title: Text('نمایش سازگار با گوشی'),
                    subtitle: Text('بدون اجازه شناور، اعلان استاندارد اندروید نمایش داده می‌شود. حباب و کارت شناور روی صفحه قفل پنهان می‌شوند؛ با قفل برنامه، متن و کد تأیید نمایش داده نمی‌شوند.'),
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
            );
            if (!pinPreview) return controls;
            return Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: preview),
              Expanded(child: controls),
            ]);
          },
        ),
      );
}

class _ActionSettings extends StatelessWidget {
  final AppSettings settings;
  const _ActionSettings({required this.settings});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return SettingsGroup(title: 'دکمه‌های کارت اعلان', children: [
      const ListTile(leading: Icon(Icons.tune_rounded), title: Text('اندازهٔ دکمه‌ها')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final size in BannerActionSize.values)
            ChoiceChip(label: Text(size.title), selected: size == s.bannerActionSize,
                onSelected: (_) => s.updateNotify(bannerActionSize: size)),
        ]),
      ),
      SwitchListTile(title: const Text('نمایش آیکون کنار عنوان'),
          value: s.bannerActionIcons, onChanged: (v) => s.updateNotify(bannerActionIcons: v)),
      SwitchListTile(title: const Text('دکمهٔ کپی کد تأیید'),
          value: s.notifyOtpCopy, onChanged: (v) => s.updateNotify(notifyOtpCopy: v)),
      if (s.notifyOtpCopy)
        SwitchListTile(title: const Text('نمایش عدد روی دکمهٔ کپی'),
            value: s.bannerActionCode, onChanged: (v) => s.updateNotify(bannerActionCode: v)),
      ExpansionTile(title: const Text('دکمه‌های دیگر'), children: [
        SwitchListTile(title: const Text('گفتگو'), value: s.notifyOpen,
            onChanged: (v) => s.updateNotify(notifyOpen: v)),
        SwitchListTile(title: const Text('بستن کارت'), value: s.notifyDismiss,
            onChanged: (v) => s.updateNotify(notifyDismiss: v)),
        SwitchListTile(title: const Text('خوانده شد در اعلان اندروید'), value: s.notifyMarkRead,
            onChanged: (v) => s.updateNotify(notifyMarkRead: v)),
        SwitchListTile(title: const Text('تماس در کارت شناور'), value: s.notifyCall,
            onChanged: (v) => s.updateNotify(notifyCall: v)),
      ]),
    ]);
  }
}

/// Colourful backdrop so the frosted glass can actually be seen in the preview.
class _PreviewStage extends StatelessWidget {
  final AppSettings settings;
  final IncomingBanner banner;
  const _PreviewStage({required this.settings, required this.banner});

  @override
  Widget build(BuildContext context) {
    final tint = banner.sourceColor == null ? settings.bannerColor : Color(banner.sourceColor!);
    return RepaintBoundary(
      key: const ValueKey('notification-style-preview'),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: settings.bannerMaxWidth),
              child: GlassBannerCard(banner: banner, settings: settings, interactive: false)),
          ),
        ]),
      ),
    ));
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
  Widget build(BuildContext context) => Semantics(
      label: const ['فیروزه‌ای', 'آبی', 'بنفش', 'اناری', 'سبز', 'کهربایی'][palettes.indexOf(color)],
      button: true, selected: selected, child: InkResponse(
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
      ));
}
