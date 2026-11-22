import 'package:flutter/material.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../message_logic.dart';
import 'failed_message_actions.dart';
import 'bulk_queue_notice.dart';
import '../sms_bridge.dart';

/// A dedicated on-device failed-SMS inbox. Only confirmed failed provider
/// rows are listed; a queued SMS is never incorrectly called "failed".
class FailedMessagesScreen extends StatefulWidget {
  final AppStore store;
  final Set<int>? restrictedIds;
  const FailedMessagesScreen({super.key, required this.store, this.restrictedIds});
  @override
  State<FailedMessagesScreen> createState() => _FailedMessagesScreenState();
}

class _FailedMessagesScreenState extends State<FailedMessagesScreen> {
  final Set<int> _selected = {};
  final Set<int> _retried = {};
  bool _busy = false;

  List<MessageRecord> get _failures => widget.store.messages
      .where((m) => m.id != null && m.failedSendOrDelivery &&
           (widget.restrictedIds == null || widget.restrictedIds!.contains(m.id)))
      .toList(growable: false);

  void _toggle(int id, bool selected) => setState(() {
    if (selected) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
  });

  Future<void> _retryBulk(List<MessageRecord> failures) async {
    if (_busy) return;
    final chosen = failures.where((m) =>
        _selected.contains(m.id) && !_retried.contains(m.id)).take(500).toList();
    if (chosen.isEmpty) return;
    final deliveryUncertain = chosen.where((m) => m.type != 5).length;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('ارسال مجدد انتخاب‌شده‌ها'),
        content: Text(
          '${Jalali.digits(chosen.length)} پیامک به‌صورت جداگانه در صف ارسال قرار می‌گیرد و ممکن است هزینه داشته باشد. '
          '${deliveryUncertain > 0 ? 'تحویل ${Jalali.digits(deliveryUncertain)} پیام قطعی نیست؛ احتمال دریافت پیام قبلی و ارسال تکراری وجود دارد. ' : ''}'
          'پیام‌های قدیمی به‌طور خودکار حذف نمی‌شوند.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('تأیید و ثبت در صف')),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    int? batchSim;
    if (widget.store.android) {
      List<Map<dynamic, dynamic>> sims;
      try {
        sims = await SmsBridge.subscriptions();
      } catch (_) {
        widget.store.onNotice?.call('شناسایی سیم‌کارت ممکن نشد.');
        return;
      }
      if (!mounted) return;
      widget.store.sims = sims;
      if (sims.isEmpty) {
        widget.store.onNotice?.call('سیم‌کارت فعال یافت نشد؛ مجوز تلفن را بررسی کنید.');
        return;
      }
      final selected = await showDialog<int>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('سیم‌کارت ارسال مجدد'),
          children: [
            for (final sim in sims)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, sim['id'] as int),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(sim['label']?.toString() ?? 'سیم‌کارت'),
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      try {
        batchSim = await SmsBridge.resolveSendSim(selected);
      } catch (_) {
        widget.store.onNotice?.call('سیم‌کارت انتخابی فعال نیست.');
        return;
      }
    }
    if (!mounted) return;
    setState(() => _busy = true);
    var queued = 0;
    try {
      for (final message in chosen) {
        // Real queue IDs are the only evidence a retry was accepted.
        final at = DateTime.now();
        final pending = await widget.store.send(
            message.sender, message.body, exactBody: true,
            groupSim: batchSim, groupTime: batchSim == null ? null : at,
            silent: true);
        if (pending != null) {
          queued++;
          _retried.add(message.id!);
          _selected.remove(message.id);
          try {
            await widget.store.smsGroups.recordRetryForFailed(
              recipient: message.sender,
              originalBody: message.body,
              originalDate: message.date,
              newBody: pending.body,
              queuedAt: at,
            );
          } catch (_) {
            widget.store.onNotice?.call('پیام در صف قرار گرفت، اما ثبت سابقهٔ گروه ممکن نشد.');
          }
        }
      }
    } finally {
      widget.store.notifyListeners();
      if (mounted) setState(() => _busy = false);
    }
    widget.store.onNotice?.call(
        '${Jalali.digits(queued)} از ${Jalali.digits(chosen.length)} پیام در صف قرار گرفت؛ وضعیت ارسال را در گفتگوها بررسی کنید.');
  }

  Future<void> _deleteBulk(List<MessageRecord> failures) async {
    if (_busy) return;
    final ids = failures.where((m) => _selected.contains(m.id))
        .map((m) => m.id!).toList(growable: false);
    if (ids.isEmpty) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('حذف پیام‌های ناموفق'),
        content: Text(
          '${Jalali.digits(ids.length)} پیامک ناموفق از حافظهٔ گوشی حذف می‌شود. '
          'این کار قابل بازگشت نیست. سوابق مستقل ارسال‌های گروهی ممکن است همچنان باقی بمانند.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('انصراف')),
          // Destructive action uses the error color.
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(dialog).colorScheme.error,
                foregroundColor: Theme.of(dialog).colorScheme.onError),
              child: const Text('حذف انتخاب‌شده‌ها')),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final deleted = await widget.store.deleteMessages(ids);
      if (deleted) {
        _selected.removeAll(ids);
        _retried.removeAll(ids);
        for (final message in failures.where((m) => ids.contains(m.id))) {
          try {
            await widget.store.smsGroups.removeFailedFromHistory(
              recipient: message.sender,
              body: message.body,
              messageDate: message.date,
            );
          } catch (_) {
            widget.store.onNotice?.call('حذف از گوشی انجام شد، اما پاک‌سازی سوابق گروه کامل نشد.');
          }
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final failures = _failures;
        final ids = failures.map((m) => m.id!).toSet();
        // Do not retain selections for messages deleted on another screen.
        _selected.removeWhere((id) => !ids.contains(id));
        final selected = failures.where((m) => _selected.contains(m.id)).length;
        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: Text(widget.restrictedIds == null ? 'پیام‌های ارسال‌نشده' : 'ناموفق‌های گروه'),
          ),
          body: Column(children: [
            const BulkQueueNotice(),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(colors: [
                  scheme.errorContainer.withValues(alpha: .6),
                  scheme.surface,
                ]),
                border: Border.all(color: scheme.error.withValues(alpha: .15)),
              ),
              child: Column(children: [
                Icon(Icons.outbox_rounded, size: 32, color: scheme.error),
                const SizedBox(height: 5),
                Text('${Jalali.digits(failures.length)} پیام نیازمند بررسی',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('ارسال‌نشده و تحویل‌ناموفق از هم مشخص‌اند. '
                    'برای ویرایش هر پیام، گزینهٔ مدیریت کنار آن را بزنید.',
                    textAlign: TextAlign.center),
              ]),
            ),
            if (failures.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  TextButton.icon(
                    onPressed: _busy ? null : () => setState(() {
                      if (selected == failures.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(ids);
                      }
                    }),
                    icon: Icon(selected == failures.length
                        ? Icons.deselect_rounded : Icons.select_all_rounded),
                    label: Text(selected == failures.length
                        ? 'لغو انتخاب' : 'انتخاب همه'),
                  ),
                  const Spacer(),
                  Text('${Jalali.digits(selected)} انتخاب‌شده',
                      style: Theme.of(context).textTheme.labelMedium),
                ]),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(child: failures.isEmpty
                ? Center(child: Column(
                    mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.task_alt_rounded, size: 60, color: scheme.primary),
                    const SizedBox(height: 8),
                    const Text('پیام ناموفقی ثبت نشده است',
                        textAlign: TextAlign.center),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: failures.length,
                    itemBuilder: (context, i) {
                      final m = failures[i];
                      final id = m.id!;
                      final sentFailed = m.type == 5;
                      final alreadyRetried = _retried.contains(id);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(children: [
                            Checkbox(
                              value: _selected.contains(id),
                              onChanged: _busy || alreadyRetried
                                  ? null : (v) => _toggle(id, v == true),
                            ),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.store.displayName(m.sender),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(m.body, maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium),
                                const SizedBox(height: 3),
                                Text(alreadyRetried ? 'تلاش مجدد ثبت شد'
                                    : sentFailed ? 'ارسال نشد' : 'تحویل ناموفق',
                                    style: TextStyle(color: alreadyRetried
                                        ? scheme.primary : scheme.error)),
                                Text(Jalali.short(m.date),
                                    style: Theme.of(context).textTheme.labelSmall),
                              ],
                            )),
                            IconButton(
                              tooltip: 'ویرایش، ارسال مجدد یا حذف',
                              icon: const Icon(Icons.more_vert_rounded),
                              onPressed: _busy || alreadyRetried
                                  ? null
                                  : () async {
                                    await failedMessageActions(
                                      context, widget.store, m,
                                      onRetried: (pending, at) async {
                                        _retried.add(id);
                                        await widget.store.smsGroups.recordRetryForFailed(
                                          recipient: m.sender,
                                          originalBody: m.body,
                                          originalDate: m.date,
                                          newBody: pending.body,
                                          queuedAt: at,
                                        );
                                      },
                                      onDeleted: () => widget.store.smsGroups.removeFailedFromHistory(
                                        recipient: m.sender,
                                        body: m.body,
                                        messageDate: m.date,
                                      ),
                                    );
                                    if (mounted) setState(() {});
                                  },
                            ),
                          ]),
                        ),
                      );
                    },
                  )),
            if (failures.isNotEmpty)
              SafeArea(top: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(children: [
                  Expanded(child: FilledButton.icon(
                    onPressed: selected == 0 || _busy
                        ? null : () => _retryBulk(failures),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('ارسال دوباره'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: selected == 0 || _busy
                        ? null : () => _deleteBulk(failures),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('حذف انتخابی'),
                  )),
                ]),
              )),
          ]),
        );
      },
    );
  }
}
