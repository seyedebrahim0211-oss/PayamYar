import 'dart:async';
import 'package:flutter/material.dart';
import '../app_store.dart';

/// Compact undo countdown that never takes up the conversation's message area.
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

class _SendControlState extends State<SendControl> {
  Timer? _timer;
  bool cancelling = false;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(covariant SendControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTimer();
  }

  void _updateTimer() {
    final active = widget.requests.any((p) => p.deadline.isAfter(DateTime.now()));
    if (!active) {
      _timer?.cancel(); _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {});
      if (!widget.requests.any((p) => p.deadline.isAfter(DateTime.now()))) {
        _timer?.cancel(); _timer = null;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final active = widget.requests.where((p) => p.deadline.isAfter(now)).toList();
    final instant = active.where((p) => !p.scheduled).toList();
    final hasScheduled = active.any((p) => p.scheduled);
    final latest = instant.isEmpty ? now
      : instant.map((p) => p.deadline).reduce((a,b) => a.isAfter(b) ? a : b);
    final remain = latest.difference(now).inMilliseconds.clamp(0, 5000);
    final undoAvailable = active.isNotEmpty && !cancelling;
    return Semantics(
      label: undoAvailable
        ? 'ارسال در صف است، برای لغو دکمه ضربدر را بزنید'
        : 'ارسال پیام، نگه‌داشتن برای ارسال زمان‌دار',
      child: SizedBox(
        width: 66, height: 63,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (instant.isNotEmpty)
            SizedBox(
              width: 59, height: 59,
              child: CircularProgressIndicator(
                value: remain / 5000,
                strokeWidth: 3.5,
                strokeCap: StrokeCap.round,
                color: scheme.tertiary,
                backgroundColor: scheme.primary.withValues(alpha: .12),
              ),
            ),
          Material(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(17),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.enabled && !widget.sending ? widget.onSend : null,
              onLongPress: widget.enabled && !widget.sending ? widget.onSchedule : null,
              child: SizedBox(
                width: 48, height: 48,
                child: Center(child: widget.sending
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(
                      strokeWidth: 2, color: scheme.onPrimary))
                  : Icon(Icons.arrow_upward_rounded, size: 26, color: scheme.onPrimary)),
              ),
            ),
          ),
          if (undoAvailable)
            PositionedDirectional(
              top: 0, end: 0,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                scale: undoAvailable ? 1 : .75,
                child: Tooltip(
                  message: hasScheduled ? 'لغو پیام زمان‌بندی‌شده' : 'لغو ارسال پیش از پایان مهلت',
                  child: SizedBox(
                    width: 28, height: 28,
                    child: IconButton.filledTonal(
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      onPressed: () async {
                        setState(() => cancelling = true);
                        try { await widget.onUndo(); }
                        finally {
                          if (mounted) { setState(() => cancelling = false); _updateTimer(); }
                        }
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
            ),
          if (hasScheduled && instant.isEmpty)
            PositionedDirectional(
              bottom: 0, start: 0,
              child: Icon(Icons.schedule_rounded, size: 16, color: scheme.tertiary),
            ),
        ]),
      ),
    );
  }
}
