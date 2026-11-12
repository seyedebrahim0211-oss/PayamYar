import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_settings.dart';
import '../app_store.dart';
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
  late final OverlayEntry _layer =
      OverlayEntry(builder: (context) => _BannerLayer(store: widget.store, settings: widget.settings));

  @override
  void didUpdateWidget(BannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _app.markNeedsBuild();
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
  late final AnimationController _show = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 460), reverseDuration: const Duration(milliseconds: 240));
  IncomingBanner? _banner;
  Timer? _timer;
  bool _typing = false;
  double _drag = 0;

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
    setState(() {
      _banner = next;
      _typing = false;
      _drag = 0;
    });
    HapticFeedback.lightImpact();
    _show.forward(from: 0);
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
    await _show.reverse();
    if (!mounted) return;
    setState(() {
      _banner = null;
      _typing = false;
      _drag = 0;
    });
    if (currentBanner.value != null) currentBanner.value = null;
  }

  void _open() {
    final b = _banner;
    if (b == null) return;
    _dismiss();
    if (b.sample) return;
    widget.store.onOpenConversation?.call(b.address);
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

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    final shown = Jalali.digits(code);
    widget.store.onNotice?.call('کد $shown کپی شد');
    _dismiss();
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
    final slide = Tween<Offset>(begin: Offset(0, top ? -1.4 : 1.4), end: Offset.zero).animate(
        CurvedAnimation(parent: _show, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic));
    return Stack(children: [
      Positioned(
        left: 10,
        right: 10,
        top: top ? media.padding.top + 8 : null,
        bottom: top ? null : media.viewInsets.bottom + media.padding.bottom + 12,
        child: Align(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SlideTransition(
              position: slide,
              child: FadeTransition(
                opacity: _show,
                child: GestureDetector(
                  onVerticalDragUpdate: (d) => _dragUpdate(d, top),
                  onVerticalDragEnd: (d) => _dragEnd(d, top),
                  child: Transform.translate(
                    offset: Offset(0, _drag),
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
    ]);
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

  const GlassBannerCard({super.key, required this.banner, required this.settings, this.interactive = true,
      this.onTap, this.onClose, this.onReply, this.onCopy, this.onTyping});

  @override
  State<GlassBannerCard> createState() => _GlassBannerCardState();
}

class _GlassBannerCardState extends State<GlassBannerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _bubbles =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));
  final _reply = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => widget.onTyping?.call(_focus.hasFocus));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBubbles();
  }

  @override
  void didUpdateWidget(GlassBannerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBubbles();
  }

  void _syncBubbles() {
    final on = widget.settings.bannerBubbles && !MediaQuery.of(context).disableAnimations;
    if (on && !_bubbles.isAnimating) {
      _bubbles.repeat();
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
    final scheme = Theme.of(context).colorScheme;
    final tint = s.bannerColor;
    final minimal = s.bannerStyle == BannerStyle.minimal;
    final glass = s.bannerStyle == BannerStyle.glass;
    final fg = minimal ? scheme.onSurface : Colors.white;
    final soft = fg.withValues(alpha: .72);
    final radius = BorderRadius.circular(26);

    final Decoration decoration;
    if (minimal) {
      decoration = BoxDecoration(
        color: scheme.surface.withValues(alpha: .97),
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      );
    } else if (glass) {
      decoration = BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.lerp(tint, Colors.black, .25)!.withValues(alpha: s.bannerOpacity),
            tint.withValues(alpha: s.bannerOpacity * .62),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .38), width: 1.2),
      );
    } else {
      decoration = BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color.lerp(tint, Colors.white, .12)!, Color.lerp(tint, Colors.black, .35)!],
        ),
      );
    }

    final hour = b.time.hour.toString().padLeft(2, '0');
    final minute = b.time.minute.toString().padLeft(2, '0');
    final clock = Jalali.digits('$hour:$minute');
    final showReply = b.canReply && s.notifyQuickReply;
    final code = b.otp;
    final codeLabel = code == null ? '' : Jalali.digits(code);

    Widget card = DecoratedBox(
      decoration: decoration,
      child: Stack(children: [
        if (s.bannerBubbles && !minimal)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _bubbles,
                builder: (context, child) => CustomPaint(painter: _BubblesPainter(_bubbles.value)),
              ),
            ),
          ),
        if (!minimal)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 46,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: .26), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                _GlassAvatar(name: b.name, tint: tint, glass: !minimal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w800, height: 1.4)),
                    Text('پیامیار • $clock', style: TextStyle(color: soft, fontSize: 11.5, height: 1.4)),
                  ]),
                ),
                if (widget.interactive)
                  IconButton(
                    onPressed: widget.onClose,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'بستن',
                    icon: Icon(Icons.close_rounded, color: soft, size: 20),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(b.body, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 14, height: 1.65)),
              if (code != null && s.notifyOtpCopy) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _GlassChip(
                    label: 'کپی کد $codeLabel',
                    icon: Icons.copy_rounded,
                    fg: fg,
                    minimal: minimal,
                    onTap: widget.interactive ? () => widget.onCopy?.call(code) : null,
                  ),
                ),
              ],
              if (showReply) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final r in s.quickReplies)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: _GlassChip(label: r, fg: fg, minimal: minimal,
                            onTap: widget.interactive ? () => _send(r) : null),
                      ),
                  ]),
                ),
                if (widget.interactive) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _reply,
                    focusNode: _focus,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(color: fg, fontSize: 14),
                    cursorColor: fg,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: minimal ? scheme.surfaceContainerHighest : Colors.white.withValues(alpha: .16),
                      hintText: 'پاسخ سریع…',
                      hintStyle: TextStyle(color: soft),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        onPressed: _send,
                        tooltip: 'ارسال',
                        icon: Icon(Icons.send_rounded, color: fg),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ]),
    );

    if (glass && s.bannerBlur > 0) {
      card = BackdropFilter(filter: ImageFilter.blur(sigmaX: s.bannerBlur, sigmaY: s.bannerBlur), child: card);
    }

    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: (minimal ? Colors.black : tint).withValues(alpha: .28), blurRadius: 28, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: InkWell(onTap: widget.interactive ? widget.onTap : null, child: card),
        ),
      ),
    );
  }
}

class _GlassAvatar extends StatelessWidget {
  final String name;
  final Color tint;
  final bool glass;
  const _GlassAvatar({required this.name, required this.tint, required this.glass});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final first = trimmed.isEmpty ? '' : trimmed.characters.first;
    final letter = RegExp(r'[0-9+۰-۹]').hasMatch(first) ? '' : first;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(tint, Colors.white, .35)!, Color.lerp(tint, Colors.black, .2)!],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .75), width: 1.6),
      ),
      child: Stack(alignment: Alignment.center, children: [
        if (glass)
          Positioned(
            top: 2,
            left: 6,
            right: 6,
            height: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: .55), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        if (letter.isEmpty)
          const Icon(Icons.person_rounded, color: Colors.white, size: 24)
        else
          Text(letter, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color fg;
  final bool minimal;
  final VoidCallback? onTap;
  const _GlassChip({required this.label, required this.fg, required this.minimal, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: minimal ? scheme.secondaryContainer : Colors.white.withValues(alpha: .18),
      shape: StadiumBorder(
          side: BorderSide(color: minimal ? Colors.transparent : Colors.white.withValues(alpha: .35))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: minimal ? scheme.onSecondaryContainer : fg),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: minimal ? scheme.onSecondaryContainer : fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Soft soap bubbles rising behind the glass.
class _BubblesPainter extends CustomPainter {
  final double t;
  _BubblesPainter(this.t);

  static final List<List<double>> _seeds = List.generate(14, (i) {
    final r = math.Random(i * 7919 + 13);
    return [r.nextDouble(), r.nextDouble(), 3 + r.nextDouble() * 9, .6 + r.nextDouble() * .8];
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final s in _seeds) {
      final p = (t * s[3] + s[1]) % 1.0;
      final radius = s[2];
      final x = s[0] * size.width + math.sin((p + s[0]) * math.pi * 2) * 10;
      final y = size.height + radius - p * (size.height + radius * 2);
      final fade = math.sin(p * math.pi);
      fill.color = Colors.white.withValues(alpha: .08 * fade);
      ring.color = Colors.white.withValues(alpha: .38 * fade);
      canvas.drawCircle(Offset(x, y), radius, fill);
      canvas.drawCircle(Offset(x, y), radius, ring);
      fill.color = Colors.white.withValues(alpha: .55 * fade);
      canvas.drawCircle(Offset(x - radius * .35, y - radius * .35), radius * .22, fill);
    }
  }

  @override
  bool shouldRepaint(_BubblesPainter oldDelegate) => oldDelegate.t != t;
}
