import 'package:flutter/material.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../templates.dart';
import '../text_polish.dart';

/// "۴۵ نویسه مانده • ۲ پیامک" under a message field.
class SmsCounter extends StatelessWidget {
  final String text;
  const SmsCounter({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final info = TextPolish.smsParts(text);
    final scheme = Theme.of(context).colorScheme;
    return Text('${Jalali.digits(info.remaining)} نویسه مانده • ${Jalali.digits(info.parts)} پیامک',
      style: TextStyle(fontSize: 11, color: info.parts > 3 ? scheme.error : scheme.onSurfaceVariant));
  }
}

/// Ready-made messages by category plus the user's own texts. Returns the chosen text.
Future<String?> showTemplatesSheet(BuildContext context, AppStore store, {String currentText = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _TemplatesSheet(store: store, currentText: currentText),
  );
}

class _TemplatesSheet extends StatefulWidget {
  final AppStore store;
  final String currentText;
  const _TemplatesSheet({required this.store, required this.currentText});
  @override
  State<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends State<_TemplatesSheet> {
  static const mine = 'پیام‌های من';
  late String group = widget.store.templates.isEmpty ? builtInTemplates.keys.first : mine;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final groups = [mine, ...builtInTemplates.keys];
        final items = group == mine ? store.templates : builtInTemplates[group]!;
        final canSave = widget.currentText.trim().isNotEmpty && !store.templates.contains(widget.currentText.trim());
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('پیام‌های آماده',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            SizedBox(height: 46, child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final g in groups)
                  Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(
                    label: Text(g), selected: group == g, showCheckmark: false,
                    onSelected: (_) => setState(() => group = g))),
              ])),
            Expanded(child: items.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24),
                    child: Text('هنوز پیامی ذخیره نکرده‌اید. متن دلخواه را بنویسید و «ذخیره متن فعلی» را بزنید.', textAlign: TextAlign.center)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => Card(child: ListTile(
                      title: Text(items[i]),
                      onTap: () => Navigator.pop(context, items[i]),
                      trailing: group == mine
                          ? IconButton(tooltip: 'حذف', icon: const Icon(Icons.close_rounded), onPressed: () => store.removeTemplate(items[i]))
                          : null)))),
            if (canSave)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: OutlinedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('ذخیره متن فعلی در پیام‌های من'),
                onPressed: () {
                  store.addTemplate(widget.currentText);
                  setState(() => group = mine);
                })),
          ]),
        );
      },
    );
  }
}

/// Text editor: fixes spelling/half-spaces/punctuation and can rewrite in a formal or polite tone.
/// Returns the edited text when the user accepts it.
Future<String?> showPolishSheet(BuildContext context, String text) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PolishSheet(text: text),
  );
}

class _PolishSheet extends StatefulWidget {
  final String text;
  const _PolishSheet({required this.text});
  @override
  State<_PolishSheet> createState() => _PolishSheetState();
}

class _PolishSheetState extends State<_PolishSheet> {
  bool fix = true, formal = false, polite = false;
  late final TextEditingController editor = TextEditingController(text: widget.text);

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = TextPolish.apply(editor.text, fix: fix, formalTone: formal, politeTone: polite);
    final changed = result != editor.text;
    final sms = TextPolish.smsParts(result);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.auto_fix_high_rounded, color: scheme.primary),
              const SizedBox(width: 9),
              Expanded(child: Text('دستیار ویرایش پیام',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              TextButton(
                onPressed: () => setState(() { editor.text = widget.text; fix = true; formal = false; polite = false; }),
                child: const Text('بازنشانی')),
            ]),
            Text('ویرایش محلی روی گوشی است؛ متن به سرور ارسال نمی‌شود.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 13),
            TextField(
              controller: editor,
              minLines: 3, maxLines: 6, maxLength: 2000,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'متن قابل ویرایش',
                hintText: 'متن دلخواهتان را اصلاح کنید…',
                prefixIcon: const Icon(Icons.edit_note_rounded),
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 5, children: [
              FilterChip(avatar: const Icon(Icons.spellcheck_rounded, size: 17),
                label: const Text('املا و نگارش'), selected: fix, onSelected: (v) => setState(() => fix = v)),
              FilterChip(label: const Text('لحن رسمی'), selected: formal, onSelected: (v) => setState(() => formal = v)),
              FilterChip(label: const Text('مؤدبانه'), selected: polite, onSelected: (v) => setState(() => polite = v)),
            ]),
            const SizedBox(height: 14),
            Text('پیش‌نمایش نهایی', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .25),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .35),
                border: Border.all(color: scheme.primary.withValues(alpha: .18)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: SingleChildScrollView(child: SelectableText(result,
                style: const TextStyle(fontSize: 15.5, height: 1.8))),
            ),
            const SizedBox(height: 7),
            Text('${Jalali.digits(result.length)} نویسه • ${Jalali.digits(sms.parts)} بخش پیامک'
                '${changed ? " • اصلاح خودکار اعمال شده" : ""}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 15),
            FilledButton.icon(
              onPressed: result.trim().isEmpty ? null : () => Navigator.pop(context, result),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('جایگزینی با متن نهایی'),
            ),
          ]),
        ),
      ),
    );
  }
}
