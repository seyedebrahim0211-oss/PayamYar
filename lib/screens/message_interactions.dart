import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../contacts/contacts_data.dart';
import '../sms_bridge.dart';

/// Shared contact actions for ordinary SMS and the optional provider inbox.
/// Nothing is saved or dialled without an explicit user action.
Future<void> showPhoneActions(BuildContext context, String raw,
    {String? displayName, VoidCallback? onMessage}) async {
  final number = phoneKey(raw);
  if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(number)) return;
  var known = displayName ?? '';
  if (known.isEmpty || known == raw || known == number) {
    try {
      final names = await SmsBridge.contactNames([number]);
      known = names[number] ?? names[raw] ?? '';
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(context: context, showDragHandle: true,
    builder: (ctx) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(known.isEmpty ? number : known),
          subtitle: known.isEmpty ? null : Text(number, textDirection: TextDirection.ltr),
          leading: const Icon(Icons.person_outline_rounded)),
        ListTile(leading: const Icon(Icons.call_outlined), title: const Text('تماس'),
          onTap: () { Navigator.pop(ctx); launchUrl(Uri(scheme: 'tel', path: number)); }),
        ListTile(leading: const Icon(Icons.sms_outlined), title: const Text('ارسال پیام'),
          onTap: () {
            Navigator.pop(ctx);
            if (onMessage != null) { onMessage(); }
            else { launchUrl(Uri(scheme: 'sms', path: number)); }
          }),
        ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('کپی شماره'),
          onTap: () { Clipboard.setData(ClipboardData(text: number)); Navigator.pop(ctx); }),
        if (known.isEmpty) ListTile(leading: const Icon(Icons.person_add_alt_rounded),
          title: const Text('ذخیره در مخاطبین'),
          onTap: () async {
            Navigator.pop(ctx);
            final nameController = TextEditingController();
            try {
              final label = await showDialog<String>(context: context, builder: (d) => AlertDialog(
                title: const Text('مخاطب جدید'),
                content: TextField(controller: nameController, maxLength: 70,
                  decoration: InputDecoration(labelText: 'نام مخاطب', helperText: number)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d), child: const Text('انصراف')),
                  FilledButton(onPressed: () => Navigator.pop(d, nameController.text.trim()),
                    child: const Text('ذخیره')),
                ],
              ));
              if (label == null || label.isEmpty) return;
              if (!context.mounted) return;
              var access = await ContactsBridge.permissions();
              if (access['write'] != true) {
                await ContactsBridge.requestPermissions();
                access = await ContactsBridge.permissions();
              }
              if (access['write'] == true) {
                await ContactsBridge.save(name: label, phones: [LabeledValue(number)]);
              } else {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('برای ذخیره مخاطب، اجازه دسترسی مخاطبین را در تنظیمات گوشی فعال کنید.')));
              }
            } catch (_) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('ذخیره مخاطب انجام نشد. مجوز مخاطبین را بررسی کنید.')));
            } finally {
              nameController.dispose();
            }
          }),
      ],
    )));
}

/// Link and phone parsing is local and deterministic. URLs only open after
/// the user reviews the exact HTTPS destination; SMS phishing needs caution.
class InteractiveMessageText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final String? senderName;
  final ValueChanged<String>? onPhoneMessage;
  const InteractiveMessageText({super.key, required this.text, this.style,
    this.senderName, this.onPhoneMessage});

  static final _pattern = RegExp(
    r'(https?://[^\s<>"،؛]+|(?:\+98|0098|0)9[0-9۰-۹٠-٩]{9})',
    caseSensitive: false);

  static String _cleanUrl(String value) => value.replaceFirst(RegExp(r'[.,،؛!?؟]+$'), '');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _pattern.allMatches(text).take(45)) {
      if (match.start > start) spans.add(TextSpan(text: text.substring(start, match.start)));
      final raw = match.group(0)!;
      final url = raw.startsWith('http');
      final value = url ? _cleanUrl(raw) : raw;
      spans.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () async {
            if (!url) {
              await showPhoneActions(context, value,
                onMessage: onPhoneMessage == null ? null : () => onPhoneMessage!(phoneKey(value)));
              return;
            }
            final uri = Uri.tryParse(value);
            if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') ||
                uri.host.isEmpty || !context.mounted) return;
            final proceed = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
              title: const Text('باز کردن لینک'),
              content: SelectableText('آدرس مقصد:\n${uri.toString()}\n\nلینک‌های ناشناس ممکن است فیشینگ باشند.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('باز کردن')),
              ],
            ));
            if (proceed == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Text(value, textDirection: TextDirection.ltr,
            style: (style ?? DefaultTextStyle.of(context).style).copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
        )));
      if (value.length != raw.length) spans.add(TextSpan(text: raw.substring(value.length)));
      start = match.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(TextSpan(style: style, children: spans), softWrap: true);
  }
}
