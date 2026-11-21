import 'package:flutter/material.dart';
import '../app_store.dart';
import '../message_logic.dart';

/// Failed SMS is a real provider row. Editing queues a NEW SMS; it never edits
/// an already attempted network message or silently deletes its audit trail.
Future<void> failedMessageActions(
  BuildContext context,
  AppStore store,
  MessageRecord message, {
  Future<void> Function(PendingSend, DateTime)? onRetried,
  Future<void> Function()? onDeleted,
}) async {
  if (!message.failedSendOrDelivery || message.id == null) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.report_gmailerrorred_rounded),
          title: Text(store.displayName(message.sender)),
          subtitle: Text(message.type == 5
              ? 'این پیام ارسال نشد.'
              : 'تحویل توسط شبکه ناموفق گزارش شده است؛ ممکن است مخاطب پیام را دریافت کرده باشد.'),
        ),
        ListTile(
          leading: const Icon(Icons.refresh_rounded),
          title: const Text('ارسال مجدد همین متن'),
          onTap: () => Navigator.pop(sheet, 'retry'),
        ),
        ListTile(
          leading: const Icon(Icons.edit_note_rounded),
          title: const Text('ویرایش و ارسال مجدد'),
          onTap: () => Navigator.pop(sheet, 'edit'),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text('حذف پیام ناموفق از گوشی'),
          onTap: () => Navigator.pop(sheet, 'delete'),
        ),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == 'delete') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('پیام ناموفق حذف شود؟'),
        content: const Text('فقط همین پیام از حافظهٔ پیامک گوشی پاک می‌شود. این کار برگشت‌پذیر نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true && await store.deleteMessages([message.id!])) {
      await onDeleted?.call();
    }
    return;
  }

  String body = message.body;
  if (choice == 'edit') {
    final controller = TextEditingController(text: body);
    final edited = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, refresh) => AlertDialog(
          title: const Text('ویرایش پیام ناموفق'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('گیرنده: ${store.displayName(message.sender)}',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 7,
              maxLength: 1000,
              onChanged: (_) => refresh(() {}),
              decoration: const InputDecoration(
                labelText: 'متن جدید',
                border: OutlineInputBorder(),
              ),
            ),
            const Text('نسخهٔ قبلی تا زمان حذف دستی در تاریخچه می‌ماند.',
                textAlign: TextAlign.center),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('انصراف')),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialog, controller.text.trim()),
              child: const Text('ثبت در صف ارسال'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (edited == null || edited.isEmpty) return;
    body = edited;
  }

  // A failed delivery acknowledgment does not prove non-receipt.
  if (message.type != 5 && context.mounted) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('احتمال ارسال تکراری'),
        content: const Text('شبکه تحویل را تأیید نکرده است. ممکن است گیرنده پیام قبلی را دریافت کرده باشد. دوباره ارسال شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('ارسال دوباره')),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  final at = DateTime.now();
  final pending = await store.send(message.sender, body, exactBody: true,
      groupTime: onRetried == null ? null : at);
  if (pending != null) {
    store.onNotice?.call('در صف ارسال مجدد قرار گرفت؛ نتیجهٔ نهایی بعداً مشخص می‌شود.');
    await onRetried?.call(pending, at);
  }
}
