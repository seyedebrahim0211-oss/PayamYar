import 'dart:async';
import 'package:flutter/material.dart';
import '../app_store.dart';
import '../jalali.dart';

/// A five-second undo surface backed by the native SMS queue deadline.
/// No "cancel" action is offered after the native cancellation window expires.
class SendUndoBar extends StatefulWidget {
  final List<PendingSend> requests;
  final Future<void> Function() onUndo;
  const SendUndoBar({super.key, required this.requests, required this.onUndo});

  @override
  State<SendUndoBar> createState() => _SendUndoBarState();
}

class _SendUndoBarState extends State<SendUndoBar> {
  Timer? _ticker;
  bool cancelling = false;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant SendUndoBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    final active = widget.requests.any((r) => r.deadline.isAfter(DateTime.now()));
    if (!active) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      if (!widget.requests.any((r) => r.deadline.isAfter(DateTime.now()))) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = widget.requests.where((r) => r.deadline.isAfter(now)).toList();
    final scheme = Theme.of(context).colorScheme;
    final scheduled = active.any((p) => p.scheduled);
    final latest = active.isEmpty ? now : active.map((p) => p.deadline)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final ms = latest.difference(now).inMilliseconds;
    final seconds = (ms.clamp(0, 5000) / 1000).ceil();

    return AnimatedSize(
      duration: const Duration(milliseconds: 310),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        reverseDuration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
        ),
        child: active.isEmpty ? const SizedBox(key: ValueKey('no-pending'))
          : Padding(
          key: ValueKey('pending-${active.first.id}'),
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .92),
              border: Border.all(color: scheme.primary.withValues(alpha: .23)),
              borderRadius: BorderRadius.circular(21),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: .11),
                blurRadius: 22, offset: const Offset(0, 7))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(13, 9, 10, 6),
                  child: Row(children: [
                    Container(
                      width: 37, height: 37,
                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12),
                        shape: BoxShape.circle),
                      child: Icon(scheduled ? Icons.schedule_send_rounded : Icons.hourglass_bottom_rounded,
                        color: scheme.primary, size: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(scheduled ? 'پیام زمان‌بندی شده' : 'فرصت لغو ارسال',
                        style: TextStyle(color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800, fontSize: 13.5)),
                      Text(scheduled ? 'زمان اجرا: ${Jalali.time(latest)}' :
                        '${Jalali.digits(active.length)} پیام • ${Jalali.digits(seconds)} ثانیه باقی مانده',
                        style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: .8),
                          fontSize: 11.5)),
                    ])),
                    const SizedBox(width: 5),
                    FilledButton.tonalIcon(
                      onPressed: cancelling ? null : () async {
                        setState(() => cancelling = true);
                        try { await widget.onUndo(); }
                        finally { if (mounted) setState(() => cancelling = false); }
                      },
                      icon: Icon(scheduled ? Icons.event_busy_rounded : Icons.undo_rounded, size: 18),
                      label: Text(active.length > 1 ? 'لغو همه' : 'لغو'),
                    ),
                  ]),
                ),
                if (!scheduled) TweenAnimationBuilder<double>(
                  key: ValueKey('countdown-${active.first.id}'),
                  tween: Tween(begin: 1, end: 0),
                  duration: Duration(milliseconds: ms.clamp(0, 5000).toInt()),
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 4,
                    backgroundColor: scheme.primary.withValues(alpha: .08),
                    color: scheme.primary,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

}
