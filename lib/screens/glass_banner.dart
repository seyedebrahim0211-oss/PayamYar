import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../app_store.dart';
import '../bank_badge.dart';
import '../jalali.dart';
import '../notify_banner.dart';
import '../sms_bridge.dart';

/// Hosts the in-app glass notification above every screen. It owns an [Overlay] so the reply
/// field (selection handles, toolbar) works even though it sits above the app's Navigator.
class BannerHost extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  final Widget child;
  const BannerHost({super.key, required this.store, required this.settings, required this.child});

  @override
  State<BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends State<BannerHost> {
  late final OverlayEntry _app = OverlayEntry(builder: (context) => widget.child);
  late final OverlayEntry _layer = OverlayEntry(
    builder: (context) => _BannerLayer(store: widget.store, settings: widget.settings),
  );

  @override
  void didUpdateWidget(BannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _app.markNeedsBuild();
    _layer.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_app, _layer]);
}

class _BannerLayer extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  const _BannerLayer({required this.store, required this.settings});

  @override
  State<_BannerLayer> createState() => _BannerLayerState();
}

class _BannerLayerState extends State<_BannerLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 140),
  );
  IncomingBanner? _banner;
  Timer? _timer;
  bool _typing = false;
  double _drag = 0;
  double _horizontal = 0;
  int _bannerGeneration = 0;

  @override
  void initState() {
    super.initState();
    currentBanner.addListener(_onBanner);
  }

  @override
  void dispose() {
    currentBanner.removeListener(_onBanner);
    _timer?.cancel();
    _show.dispose();
    super.dispose();
  }

  void _onBanner() {
    final next = currentBanner.value;
    if (next == null) {
      _dismiss();
      return;
    }
    if (!next.sample && !widget.settings.notifyInApp) return;
    _bannerGeneration++;
    setState(() {
      _banner = next;
      _typing = false;
      _drag = 0;
      _horizontal = 0;
    });
    HapticFeedback.lightImpact();
    if (widget.settings.reduceEffects || MediaQuery.disableAnimationsOf(context)) {
      _show.value = 1;
    } else {
      _show.forward(from: 0);
    }
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_typing) return;
    _timer = Timer(Duration(seconds: widget.settings.bannerSeconds), _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted || _banner == null) return;
    final generation = ++_bannerGeneration;
    final dismissed = _banner;
    if (widget.settings.reduceEffects || MediaQuery.disableAnimationsOf(context)) {
      _show.value = 0;
    } else {
      await _show.reverse();
    }
    if (!mounted || generation != _bannerGeneration) return;
    setState(() {
      _banner = null;
      _typing = false;
      _drag = 0;
      _horizontal = 0;
    });
    // A newer SMS may arrive while the old card is animating out.
    // Only clear the exact banner dismissed, never the new message.
    if (identical(currentBanner.value, dismissed)) currentBanner.value = null;
  }

  void _open() {
    final b = _banner;
    if (b == null) return;
    if (b.sample) {
      _dismiss();
      return;
    }
    // Never dismiss a real message unless the main conversation can be opened.
    final openConversation = widget.store.onOpenConversation;
    if (openConversation == null) {
      widget.store.onNotice?.call('گفتگو هنوز آماده نیست؛ پیام در صندوق پیامک‌ها باقی می‌ماند.');
      return;
    }
    openConversation(b.address);
    _dismiss();
    SmsBridge.clearNotifications(b.address);
  }

  Future<void> _reply(String text) async {
    final b = _banner;
    if (b == null || text.trim().isEmpty) return;
    _dismiss();
    if (b.sample) {
      widget.store.onNotice?.call('این فقط نمونه بود؛ پیامی ارسال نشد.');
      return;
    }
    final name = b.name;
    final sent = await widget.store.send(b.address, text);
    if (sent != null) widget.store.onNotice?.call('پاسخ به $name در صف ارسال است.');
  }

  Future<void> _copy(String code) async {
    final banner = _banner;
    try {
      await SmsBridge.copyOtp(code);
      if (!mounted) return;
      if (identical(_banner, banner)) _dismiss();
    } on PlatformException {
      if (mounted) widget.store.onNotice?.call('کپی کد انجام نشد. دوباره لمس کنید.');
    }
  }

  Future<void> _horizontalEnd(DragEndDetails details) async {
    final b = _banner;
    final dx = _horizontal;
    setState(() => _horizontal = 0);
    if (b == null || dx.abs() < 44 || _typing) {
      _restartTimer();
      return;
    }
    final read = dx > 0 ? widget.settings.swipeRightRead : widget.settings.swipeLeftRead;
    if (read && !b.sample) {
      try {
        await SmsBridge.readBanner(b.address, b.time);
        if (mounted) unawaited(widget.store.refresh());
      } on PlatformException {
        if (mounted) widget.store.onNotice?.call('علامت‌گذاری پیام انجام نشد.');
      }
    }
    if (mounted && identical(_banner, b)) await _dismiss();
  }

  void _dragUpdate(DragUpdateDetails d, bool top) {
    setState(() => _drag = top ? math.min(0.0, _drag + d.delta.dy) : math.max(0.0, _drag + d.delta.dy));
  }

  void _dragEnd(DragEndDetails d, bool top) {
    final v = d.primaryVelocity ?? 0;
    if ((top && (_drag < -36 || v < -500)) || (!top && (_drag > 36 || v > 500))) {
      _dismiss();
    } else {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _banner;
    if (b == null) return const SizedBox.shrink();
    final top = widget.settings.bannerTop;
    final media = MediaQuery.of(context);
    final slide = Tween<Offset>(
      begin: Offset(0, top ? -1.4 : 1.4),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_show);
    final tilt = Tween<double>(begin: top ? -.04 : .04, end: 0).animate(_show);
    return Stack(
      children: [
        Positioned(
          left: 10,
          right: 10,
          top: top ? media.padding.top + 8 : null,
          bottom: top ? null : media.viewInsets.bottom + media.padding.bottom + 12,
          child: Align(
            alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: widget.settings.bannerMaxWidth,
                maxHeight: math.max(
                  1.0,
                  media.size.height - media.viewInsets.bottom - media.padding.vertical - 24,
                ),
              ),
              child: SlideTransition(
                position: slide,
                child: FadeTransition(
                  opacity: _show,
                  child: AnimatedBuilder(
                    animation: tilt,
                    builder: (context, child) => Transform(
                      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .001)
                        ..rotateX(tilt.value),
                      child: child,
                    ),
                    child: GestureDetector(
                      onHorizontalDragStart: (_) => _timer?.cancel(),
                      onHorizontalDragUpdate: (d) => setState(() => _horizontal += d.delta.dx),
                      onHorizontalDragEnd: _horizontalEnd,
                      onHorizontalDragCancel: () {
                        setState(() => _horizontal = 0);
                        _restartTimer();
                      },
                      onVerticalDragUpdate: (d) => _dragUpdate(d, top),
                      onVerticalDragEnd: (d) => _dragEnd(d, top),
                      child: Transform.translate(
                        offset: Offset(_horizontal, _drag),
                        child: GlassBannerCard(
                          key: ValueKey(b),
                          banner: b,
                          settings: widget.settings,
                          onTap: _open,
                          onClose: _dismiss,
                          onReply: _reply,
                          onCopy: _copy,
                          onTyping: (typing) {
                            _typing = typing;
                            _restartTimer();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The glass card itself; also used as the live preview in notification settings.
class GlassBannerCard extends StatefulWidget {
  final IncomingBanner banner;
  final AppSettings settings;
  final bool interactive;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final ValueChanged<String>? onReply;
  final ValueChanged<String>? onCopy;
  final ValueChanged<bool>? onTyping;

  const GlassBannerCard({
    super.key,
    required this.banner,
    required this.settings,
    this.interactive = true,
    this.onTap,
    this.onClose,
    this.onReply,
    this.onCopy,
    this.onTyping,
  });

  @override
  State<GlassBannerCard> createState() => _GlassBannerCardState();
}

class _GlassBannerCardState extends State<GlassBannerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _bubbles = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  final _reply = TextEditingController();
  final _focus = FocusNode();
  bool _expanded = false;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => widget.onTyping?.call(_expanded || _focus.hasFocus));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBubbles();
  }

  @override
  void didUpdateWidget(GlassBannerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banner != widget.banner && !widget.banner.sample) {
      _expanded = false;
      _writing = false;
    }
    _syncBubbles();
  }

  void _syncBubbles() {
    final on =
        widget.settings.bannerBubbles &&
        !widget.settings.reduceEffects &&
        !MediaQuery.disableAnimationsOf(context);
    if (on && !_bubbles.isAnimating && !_bubbles.isCompleted) {
      _bubbles.forward();
    } else if (!on && _bubbles.isAnimating) {
      _bubbles.stop();
    }
  }

  @override
  void dispose() {
    _bubbles.dispose();
    _reply.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final value = (text ?? _reply.text).trim();
    if (value.isEmpty) return;
    _reply.clear();
    _focus.unfocus();
    widget.onReply?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final b = widget.banner;
    final tint = s.bannerSourceColors && b.sourceColor != null ? Color(b.sourceColor!) : s.bannerColor;
    final rim = 2 + 4 * s.bannerEdge;
    final radius = BorderRadius.circular(s.bannerCorner);
    final inner = BorderRadius.circular(s.bannerCorner - rim);
    final alpha = .65 + .35 * s.bannerOpacity;
    final luma = (54 * tint.r + 183 * tint.g + 19 * tint.b) * 255 / 256;
    final topScale = math.min(.82, 70 / math.max(1.0, luma));
    final clock = Jalali.digits(
      '${b.time.hour.toString().padLeft(2, '0')}:${b.time.minute.toString().padLeft(2, '0')}',
    );
    final code = b.otp;
    final chipCode = code != null && s.notifyOtpCopy;
    final showReply = _expanded && b.canReply && s.notifyQuickReply;
    final reduce = s.reduceEffects || MediaQuery.disableAnimationsOf(context);

    void toggle() {
      setState(() {
        _expanded = !_expanded;
        _writing = false;
      });
      if (!_expanded) _focus.unfocus();
      widget.onTyping?.call(_expanded);
    }

    final messageText = Text(
      b.body,
      maxLines: _expanded ? null : 2,
      overflow: _expanded ? null : TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.55),
    );
    Widget face = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color.lerp(tint, Colors.black, 1 - topScale)!.withValues(alpha: alpha),
            Color.lerp(tint, Colors.black, 1 - topScale * .66)!.withValues(alpha: alpha),
          ],
        ),
      ),
      child: Stack(
        children: [
          if (s.bannerBubbles)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: CustomPaint(painter: _BubblesPainter(_bubbles))),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 36,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: s.bannerShine * .10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    BankBadge(sender: b.showBrand && s.notifyPreview ? b.address : '',
                      size: 42, square: s.notifyAvatarShape == 1,
                      fallback: _GlassAvatar(
                      name: b.name,
                      tint: tint,
                      glass: s.notifyGlassAvatar,
                      square: s.notifyAvatarShape == 1,
                    )),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              height: 1.38,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'پیام‌یار · $clock',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xF2FFFFFF), fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    if (widget.interactive || b.sample)
                      IconButton(
                        onPressed: toggle,
                        tooltip: _expanded ? 'جمع کردن اعلان' : 'نمایش متن کامل',
                        icon: Icon(
                          _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (!_expanded) messageText,
                if (chipCode || showReply || (_expanded && (s.notifyOpen || s.notifyDismiss))) ...[
                  Wrap(
                    spacing: 4,
                    children: [
                      if (chipCode)
                        _GlassChip(
                          settings: s,
                          label: s.bannerActionCode ? 'کپی کد ${Jalali.digits(code)}' : 'کپی کد',
                          shortLabel: 'کپی کد',
                          icon: Icons.copy_rounded,
                          onTap: widget.interactive ? () => widget.onCopy?.call(code) : null,
                        ),
                      if (showReply && !_writing)
                        _GlassChip(
                          settings: s,
                          label: 'پاسخ',
                          icon: Icons.reply_rounded,
                          onTap: !widget.interactive ? null : () {
                            setState(() => _writing = true);
                            _focus.requestFocus();
                          },
                        ),
                      if (_expanded && s.notifyOpen)
                        _GlassChip(settings: s, label: 'گفتگو', icon: Icons.chat_bubble_outline_rounded, onTap: widget.onTap),
                      if (_expanded && s.notifyDismiss)
                        _GlassChip(settings: s, label: 'بستن', icon: Icons.close_rounded,
                            onTap: widget.interactive ? widget.onClose : toggle),
                    ],
                  ),
                ],
                if (showReply && _writing) ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _reply,
                    focusNode: _focus,
                    onSubmitted: _send,
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'پاسخ سریع…',
                      hintStyle: const TextStyle(color: Color(0xDDFFFFFF)),
                      filled: true,
                      fillColor: const Color(0x33000000),
                      suffixIcon: IconButton(
                        onPressed: _send,
                        tooltip: 'ارسال',
                        icon: const Icon(Icons.send_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      for (final reply in s.quickReplies)
                        _GlassChip(settings: s, label: reply, onTap: () => _send(reply)),
                    ],
                  ),
                ],
                if (_expanded) messageText,
              ],
            ),
          ),
        ],
      ),
    );
    if (s.bannerBlur > 0 && !reduce && widget.interactive) {
      face = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: s.bannerBlur / 2, sigmaY: s.bannerBlur / 2),
        child: face,
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .65),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              if (!reduce)
                BoxShadow(color: tint.withValues(alpha: .22), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: CustomPaint(
            painter: _GlassRim(tint, s.bannerCorner, rim),
            child: Padding(
              padding: EdgeInsets.all(rim),
              child: ClipRRect(
                borderRadius: inner,
                child: InkWell(onTap: widget.interactive ? widget.onTap : null, child: face),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassRim extends CustomPainter {
  final Color tint;
  final double radius;
  final double inset;
  const _GlassRim(this.tint, this.radius, this.inset);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(bounds, Radius.circular(radius));
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(tint, Colors.white, .59)!,
          Color.lerp(tint, const Color(0xFFF5E8C8), .83)!,
          Color.lerp(tint, Colors.white, .34)!,
        ],
      ).createShader(bounds);
    canvas.drawDRRect(outer, outer.deflate(inset), paint);
  }

  @override
  bool shouldRepaint(_GlassRim old) => old.tint != tint || old.radius != radius || old.inset != inset;
}

class _GlassAvatar extends StatelessWidget {
  final String name;
  final Color tint;
  final bool glass;
  final bool square;
  const _GlassAvatar({required this.name, required this.tint, required this.glass, required this.square});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().characters.firstOrNull;
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(square ? 12 : 22),
          border: Border.all(color: const Color(0xCBFFFFFF), width: 1.3),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(tint, Colors.white, glass ? .32 : .04)!, Color.lerp(tint, Colors.black, .3)!],
          ),
        ),
        child: initial == null || RegExp(r'^[+\d۰-۹٠-٩]').hasMatch(initial)
            ? const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20)
            : Text(
                initial,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final AppSettings settings;
  final String label;
  final String? shortLabel;
  final IconData? icon;
  final VoidCallback? onTap;
  const _GlassChip({required this.settings, required this.label, this.shortLabel, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = settings.bannerActionSize;
    final textStyle = Theme.of(context).textTheme.labelMedium!.copyWith(
      fontSize: size.font, height: 1.22, fontWeight: FontWeight.w600, letterSpacing: 0,
    );
    final primary = shortLabel != null;
    return LayoutBuilder(builder: (context, bounds) {
      final showIcon = settings.bannerActionIcons && icon != null &&
          bounds.maxWidth >= size.padding * 2 + size.icon + 32;
      var visibleLabel = label;
      // Preserve the entire OTP or omit the digits. A partly visible code is misleading.
      if (shortLabel != null && label != shortLabel) {
        final measure = TextPainter(
          text: TextSpan(text: label, style: textStyle), textDirection: TextDirection.rtl,
          textScaler: MediaQuery.textScalerOf(context), maxLines: 1,
        )..layout();
        final needed = measure.width.ceil() + 2 * size.padding + (showIcon ? size.icon + 4 : 0);
        measure.dispose();
        if (needed > bounds.maxWidth) visibleLabel = shortLabel!;
      }
      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white, disabledForegroundColor: Colors.white,
          backgroundColor: primary ? const Color(0x30FFFFFF) : const Color(0x19FFFFFF),
          side: BorderSide(color: primary ? const Color(0x72FFFFFF) : const Color(0x44FFFFFF)),
          shape: const StadiumBorder(), minimumSize: Size(48, size.height),
          padding: EdgeInsets.symmetric(horizontal: size.padding, vertical: 2),
          tapTargetSize: MaterialTapTargetSize.padded, visualDensity: VisualDensity.standard,
          textStyle: textStyle,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (showIcon) ...[Icon(icon, size: size.icon), const SizedBox(width: 4)],
          Flexible(child: Text(visibleLabel, softWrap: false, maxLines: 1,
              overflow: TextOverflow.ellipsis, semanticsLabel: label)),
        ]),
      );
    });
  }
}

/// Only the seven rings repaint during the brief entry motion.
class _BubblesPainter extends CustomPainter {
  final Animation<double> motion;
  _BubblesPainter(this.motion) : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x33FFFFFF);
    for (var i = 0; i < 7; i++) {
      final x = size.width * ((i * 37 + 9) % 100) / 100;
      final y = size.height * ((i * 29 + 13) % 100) / 100;
      canvas.drawCircle(Offset(x, y + (1 - motion.value) * 4), 5.0 + i % 3 * 2, ring);
    }
  }

  @override
  bool shouldRepaint(_BubblesPainter old) => old.motion != motion;
}
