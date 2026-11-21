import 'package:flutter/material.dart';
import '../app_store.dart';
import '../message_logic.dart';

Future<void> failedMessageActions(BuildContext context, AppStore store, MessageRecord message,
    {Future<void> Function(PendingSend)? onRetried, Future<void> Function()? onDeleted}) async {
  if (!message.failedSendOrDelivery || message.id == null) return;
  final retry = await showModalBottomSheet<bool>(context: context, showDragHandle: true,
    builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: Text(message.sender, textDirection: TextDirection.ltr),
        subtitle: Text(message.type == 5 ? 'ارسال این پیام ناموفق بود.' : 'شبکه تحویل این پیام را ناموفق گزارش کرد.')),
      ListTile(leading: const Icon(Icons.refresh), title: const Text('ارسال مجدد'),
        onTap: () => Navigator.pop(sheet, true)),
      ListTile(leading: const Icon(Icons.delete_outline), title: const Text('پاک کردن'),
        onTap: () => Navigator.pop(sheet, false)),
    ])));
  if (retry == null || !context.mounted) return;
  if (retry) {
    final pending = await store.send(message.sender, message.body, exactBody: true);
    if (pending != null) {
      store.onNotice?.call('ارسال مجدد برای همین شماره در صف قرار گرفت.');
      await onRetried?.call(pending);
    }
  } else {
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) =>
      AlertDialog(title: const Text('این پیام از گوشی پاک شود؟'), actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('پاک کردن')),
      ]));
    if (confirmed == true && await store.deleteMessages([message.id!])) await onDeleted?.call();
  }
}
