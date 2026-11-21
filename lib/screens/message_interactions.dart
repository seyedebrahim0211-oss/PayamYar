import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../contacts/contacts_data.dart';
import '../search_highlight.dart';
import '../sms_bridge.dart';
import 'contact_action_card.dart';

/// Shared contact actions for ordinary SMS and the optional provider inbox.
/// Nothing is saved or dialled without an explicit user action.
Future<void> showPhoneActions(BuildContext context, String raw,
    {String? displayName, VoidCallback? onMessage}) =>
  showContactActionCard(context, raw,
    displayName: displayName, onMessage: onMessage);

/// Link and phone parsing is local and deterministic. URLs only open after
/// the user reviews the exact HTTPS destination; SMS phishing needs caution.
class InteractiveMessageText extends StatelessWidget {
  final String text;
  final String searchQuery;
  final TextStyle? style;
  final String? senderName;
  final ValueChanged<String>? onPhoneMessage;
  const InteractiveMessageText({super.key, required this.text, this.searchQuery = '', this.style,
    this.senderName, this.onPhoneMessage});

  static const _digit = '[0-9۰-۹٠-٩]';
  static const _numeric = r'(?:IR[ \t-]*(?:D[ \t-]*){23}D|(?:D{4}[ -]){3}D{4}|(?:\+?D+[\-/.])+D+|\+?D+)';
  static final _pattern = RegExp(
    r'(?:https?://|www\.)[^\s<>"،؛]+|(?:[a-z0-9-]+\.)+(?:ir|com|net|org|io|app)(?![a-z0-9.-])(?:[/\?#][^\s<>"،؛]*)?|'
    r'(?:\+98|0098|0|\+۹۸|۰۰۹۸|۰|\+٩٨|٠٠٩٨|٠)[9۹٩](?:[0-9۰-۹٠-٩][ -]?){8}[0-9۰-۹٠-٩](?![0-9۰-۹٠-٩])|'
    + _numeric.replaceAll('D', _digit), caseSensitive: false);

  static final _urlStart = RegExp(r'^(?:https?://|www\.|(?:[a-z0-9-]+\.)+(?:ir|com|net|org|io|app))', caseSensitive: false);
  static final _mobile = RegExp(r'^(?:\+98|0098|0)9[0-9]{9}$');

  static String _cleanUrl(String value) => value.replaceFirst(RegExp(r'[.,،؛!?؟]+$'), '');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _pattern.allMatches(text).take(45)) {
      if (match.start > start) spans.add(searchHighlight(text.substring(start, match.start), searchQuery));
      final raw = match.group(0)!;
      final url = _urlStart.hasMatch(raw);
      if (match.start > 0 && text[match.start - 1] == '@' && url) {
        spans.add(TextSpan(text: raw));
        start = match.end;
        continue;
      }
      final value = url ? _cleanUrl(raw) : raw;
      final compact = SmsBridge.normalizeNumber(value).toUpperCase().replaceAll(RegExp(r'[ \t-]'), '');
      final mobile = !url && _mobile.hasMatch(compact);
      spans.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onLongPress: mobile ? () => showPhoneActions(context, value,
            onMessage: onPhoneMessage == null ? null : () => onPhoneMessage!(phoneKey(value))) : null,
          onTap: () async {
            if (!url) {
              await Clipboard.setData(ClipboardData(text: compact));
              if (context.mounted) {
                ScaffoldMessenger.of(context)..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('شماره کپی شد.')));
              }
              return;
            }
            final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
            if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') ||
                uri.host.isEmpty || uri.userInfo.isNotEmpty || !context.mounted) { return; }
            final proceed = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
              title: const Text('باز کردن لینک'),
              content: SingleChildScrollView(child: SelectableText(uri.toString(), textDirection: TextDirection.ltr)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
                TextButton(onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: uri.toString()));
                  if (d.mounted) Navigator.pop(d, false);
                }, child: const Text('کپی آدرس')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('باز کردن در مرورگر')),
              ],
            ));
            if (proceed != true) return;
            try {
              if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
            } catch (_) {
              // Android may have no enabled activity for this web address.
            }
            if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('مرورگر باز نشد. آدرس را از کارت لینک کپی کنید.'))); }
          },
          child: url
            ? Chip(avatar: const Icon(Icons.open_in_browser, size: 16), label: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
                style: (style ?? DefaultTextStyle.of(context).style).copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800, decoration: TextDecoration.underline)))
            : !mobile ? Text(value, textDirection: TextDirection.ltr,
                style: (style ?? DefaultTextStyle.of(context).style).copyWith(
                  fontWeight: FontWeight.w700, decoration: TextDecoration.underline))
            : FutureBuilder<String?>(
                future: ContactNameLookup.resolve(phoneKey(value)),
                builder: (ctx, result) {
                  final saved = result.data;
                  final label = saved == null || saved.isEmpty ? value : saved;
                  final scheme = Theme.of(ctx).colorScheme;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(9)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.person_rounded, size: 14, color: scheme.onPrimaryContainer),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(ctx).width * .50),
                        child: Text(label,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          textDirection: saved == null ? TextDirection.ltr : TextDirection.rtl,
                          style: TextStyle(fontWeight: FontWeight.w800,
                            color: scheme.onPrimaryContainer,
                            fontSize: (style?.fontSize ?? 15) - 1,
                            decoration: TextDecoration.underline)),
                      ),
                    ]),
                  );
                }),
        )));
      if (value.length != raw.length) spans.add(TextSpan(text: raw.substring(value.length)));
      start = match.end;
    }
    if (start < text.length) spans.add(searchHighlight(text.substring(start), searchQuery));
    return Text.rich(TextSpan(style: style, children: spans), softWrap: true);
  }
}
