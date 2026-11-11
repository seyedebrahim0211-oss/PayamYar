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
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
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
    if (active.isEmpty || cancelling) return const SizedBox.shrink();

    final latest = active.map((p) => p.deadline)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final left = latest.difference(now).inMilliseconds.clamp(0, 5000);
    final count = active.length;
    final seconds = (left / 1000).ceil();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        elevation: 2,
        color: scheme.primaryContainer,
        shadowColor: scheme.shadow.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 8, 4),
              child: Row(children: [
                Icon(Icons.schedule_send_rounded, size: 20,
                  color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  count > 1 ? '$count پیامک در صف ارسال' : 'پیامک در صف ارسال',
                  style: TextStyle(color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
                Text('${Jalali.digits(seconds)} ثانیه',
                  style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12)),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: cancelling ? null : () async {
                    setState(() => cancelling = true);
                    try {
                      await widget.onUndo();
                    } finally {
                      if (mounted) setState(() => cancelling = false);
                    }
                  },
                  child: Text(count > 1 ? 'لغو همه' : 'لغو ارسال',
                    style: TextStyle(color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            LinearProgressIndicator(
              value: left / 5000,
              minHeight: 3,
              backgroundColor: scheme.onPrimaryContainer.withValues(alpha: .12),
              color: scheme.primary,
            ),
          ]),
        ),
      ),
    );
  }
}
