import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../jalali.dart';

/// Round send button. While a message waits in its undo window, a ring around the
/// same circle drains with the remaining delay and the arrow turns into ✕: one tap
/// cancels and puts the text back. Long-press opens scheduled sending.
/// The native queue is authoritative: an expired request cannot be cancelled here.
class SendControl extends StatefulWidget {
  final List<PendingSend> requests;
  final Future<void> Function() onUndo;
  final VoidCallback onSend;
  final VoidCallback? onSchedule;
  final bool sending;
  final bool enabled;
  const SendControl({
    super.key, required this.requests, required this.onUndo, required this.onSend,
    this.onSchedule, this.sending = false, this.enabled = true,
  });
  @override
  State<SendControl> createState() => _SendControlState();
}

class _SendControlState extends State<SendControl> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _tick());
  bool cancelling = false;

  bool get _active => widget.requests.any((p) => !p.scheduled && p.deadline.isAfter(DateTime.now()));

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (!_active && _ticker.isActive) _ticker.stop();
  }

  void _sync() {
    if (_active && !_ticker.isActive) _ticker.start();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SendControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    HapticFeedback.lightImpact();
    setState(() => cancelling = true);
    try { await widget.onUndo(); }
    finally { if (mounted) setState(() => cancelling = false); }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final instant = widget.requests.where((p) => !p.scheduled && p.deadline.isAfter(now)).toList();
    final scheduled = widget.requests.any((p) => p.scheduled && p.deadline.isAfter(now));
    PendingSend? last;
    for (final p in instant) {
      if (last == null || p.deadline.isAfter(last.deadline)) last = p;
    }
    final total = last == null ? 1 : math.max(1, last.window.inMilliseconds);
    final remain = last == null ? 0 : last.deadline.difference(now).inMilliseconds.clamp(0, total);
    final counting = last != null && !cancelling;
    final seconds = (remain / 1000).ceil();
    const size = 54.0;

    return Semantics(
      button: true,
      label: counting ? 'لغو ارسال، ${Jalali.digits(seconds)} ثانیه باقی مانده' : 'ارسال پیام؛ لمس طولانی برای ارسال زمان‌دار',
      child: SizedBox(
        width: size + 8, height: size + 8,
        child: Stack(alignment: Alignment.center, children: [
          // Countdown ring around the button.
          SizedBox(
            width: size + 8, height: size + 8,
            child: CustomPaint(painter: _RingPainter(
              progress: counting ? remain / total : 0,
              color: scheme.tertiary,
              track: scheme.primary.withValues(alpha: counting ? .16 : 0))),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
                colors: counting
                    ? [scheme.errorContainer, scheme.errorContainer]
                    : [Color.lerp(scheme.primary, Colors.white, .12)!, scheme.primary]),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: .28), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: counting ? _cancel
                    : widget.enabled && !widget.sending ? widget.onSend : null,
                onLongPress: !counting && widget.enabled && !widget.sending ? widget.onSchedule : null,
                child: Center(child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: widget.sending
                      ? SizedBox(key: const ValueKey('busy'), width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.onPrimary))
                      : counting
                          ? Column(key: const ValueKey('cancel'), mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.close_rounded, size: 24, color: scheme.onErrorContainer),
                              Text(Jalali.digits(seconds), style: TextStyle(fontSize: 10, height: 1,
                                fontWeight: FontWeight.w800, color: scheme.onErrorContainer)),
                            ])
                          : Transform.rotate(
                              key: const ValueKey('send'),
                              angle: math.pi, // RTL: the paper plane points left, toward the reader's flow
                              child: Icon(Icons.send_rounded, size: 24, color: scheme.onPrimary)),
                )),
              ),
            ),
          ),
          if (scheduled && !counting)
            PositionedDirectional(
              bottom: 0, start: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                child: Icon(Icons.schedule_rounded, size: 15, color: scheme.tertiary)),
            ),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  const _RingPainter({required this.progress, required this.color, required this.track});
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = track..style = PaintingStyle.stroke..strokeWidth = 3.5);
    if (progress <= 0) return;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * progress, false, Paint()
      ..color = color..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
