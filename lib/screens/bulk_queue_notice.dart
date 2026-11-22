import 'dart:async';
import 'package:flutter/material.dart';
import '../sms_bridge.dart';
import '../jalali.dart';

/// Small on-device-only view of the durable, carrier-aware SMS queue.
/// A queued SMS must not be described as delivered.
class BulkQueueNotice extends StatefulWidget {
  const BulkQueueNotice({super.key});

  @override
  State<BulkQueueNotice> createState() => _BulkQueueNoticeState();
}

class _BulkQueueNoticeState extends State<BulkQueueNotice> {
  Timer? _poll;
  bool _loading = false;
  int _queued = 0;
  bool _waiting = false;
  bool _paused = false;
  String _reason = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!SmsBridge.supported || _loading) return;
    _loading = true;
    try {
      final state = await SmsBridge.bulkState();
      if (!mounted) return;
      setState(() {
        _queued = (state['queued'] as num?)?.toInt() ?? 0;
        _waiting = state['waiting'] == true;
        _paused = state['paused'] == true;
        _reason = state['reason']?.toString() ?? '';
      });
    } catch (_) {
      // Failure to read diagnostics cannot block sending or navigation.
    } finally {
      _loading = false;
    }
  }

  Future<void> _resume() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('ادامه صف ارسال؟'),
        content: const Text(
          'ابتدا وضعیت پیام قبلی را در گفتگو بررسی کنید. پیام قبلی به‌طور خودکار '
          'تکرار نمی‌شود؛ فقط پیام‌های باقی‌مانده صف با فاصله و پس از '
          'تأیید شبکه ارسال خواهند شد. محدودیت اپراتور همچنان برقرار است.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('ادامه پیام‌های باقی‌مانده')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      final started = await SmsBridge.resumeBulk();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(started
          ? 'ارسال پیام‌های باقی‌مانده از سر گرفته شد.'
          : 'پیام دیگری در صف باقی نمانده است.'),
      ));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ادامه صف ممکن نشد؛ مجوزها و سیم‌کارت را بررسی کنید.')));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_queued == 0 && !_paused && !_waiting) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _paused ? colors.errorContainer.withValues(alpha: .6)
          : colors.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _paused ? colors.error.withValues(alpha: .3)
          : colors.primary.withValues(alpha: .2)),
      ),
      child: Row(children: [
        Icon(_paused ? Icons.pause_circle_outline_rounded : Icons.schedule_send_rounded,
          color: _paused ? colors.error : colors.primary),
        const SizedBox(width: 9),
        Expanded(child: Text(_paused
          ? 'صف ارسال متوقف است. ${_reason.isEmpty ? 'وضعیت شبکه را بررسی کنید.' : _reason}'
          : '${Jalali.digits(_queued)} پیام در صف کنترل‌شده؛ '
            'ارسال به ترتیب و با تأیید شبکه انجام می‌شود.',
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 3, overflow: TextOverflow.ellipsis)),
        if (_paused && _queued > 0)
          TextButton(onPressed: _resume, child: const Text('ادامه صف')),
      ]),
    );
  }
}
