import 'package:flutter/material.dart';
import 'contact_store.dart';
import 'contacts_data.dart';

/// Offline name-based suggestions. No automatic relationship inference is saved.
class FamilyRelations {
  static const labels = ['پدر', 'مادر', 'همسر', 'پسر', 'دختر', 'برادر', 'خواهر',
    'پدربزرگ', 'مادربزرگ', 'عمو', 'عمه', 'دایی', 'خاله', 'سایر'];
  static String? suggest(String name) {
    final v = name.toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک')
      .replaceAll('‌', ' ').trim();
    for (final label in ['پدربزرگ', 'مادربزرگ', 'برادر', 'خواهر', 'پدر',
      'مادر', 'همسر', 'عمو', 'عمه', 'دایی', 'خاله', 'پسر', 'دختر']) {
      if (v == label || v.startsWith('$label ') || v.endsWith(' $label') ||
          v.contains(' $label ')) { return label; }
    }
    if (v == 'بابا' || v.startsWith('بابا ')) { return 'پدر'; }
    if (v == 'مامان' || v.startsWith('مامان ')) { return 'مادر'; }
    return null;
  }
}

class FamilyScreen extends StatefulWidget {
  final ContactStore contacts;
  const FamilyScreen({super.key, required this.contacts});
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}
class _FamilyScreenState extends State<FamilyScreen> {
  final Map<String, String> relations = {};
  final Set<String> excluded = {};
  bool showSuggestions = true;
  bool loaded = false;

  @override
  void initState() { super.initState(); _restore(); }

  Future<void> _restore() async {
    final values = await widget.contacts.familyRelations();
    if (!mounted) return;
    setState(() { relations.addAll(values); loaded = true; });
  }

  Future<void> _set(PhoneContact contact, String? relation) async {
    if (relation == null) return;
    await widget.contacts.setFamilyRelation(contact, relation == 'حذف از خانواده' ? null : relation);
    if (!mounted) return;
    final next = await widget.contacts.familyRelations();
    setState(() { relations..clear()..addAll(next); excluded.add(contact.key); });
  }

  Future<void> _edit(PhoneContact c, String? proposed) async {
    final selected = await showModalBottomSheet<String>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true,
        children: [
          ListTile(title: Text(c.displayName), subtitle: const Text('رابطه را خودتان تأیید یا تعیین کنید')),
          for (final label in FamilyRelations.labels)
            ListTile(title: Text(label),
              leading: Icon(label == (relations[c.key] ?? proposed) ? Icons.check_circle : Icons.person_outline),
              onTap: () => Navigator.pop(ctx, label)),
          ListTile(title: const Text('نوشتن نسبت دلخواه'),
            leading: const Icon(Icons.edit_note_rounded),
            onTap: () => Navigator.pop(ctx, '_custom_')),
          ListTile(title: const Text('حذف از خانواده'),
            leading: const Icon(Icons.person_remove_outlined),
            onTap: () => Navigator.pop(ctx, 'حذف از خانواده')),
        ])),
    );
    if (selected == '_custom_' && mounted) {
      final controller = TextEditingController(text: relations[c.key] ?? '');
      final custom = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('عنوان نسبت خانوادگی'),
          content: TextField(controller: controller, maxLength: 30,
            decoration: const InputDecoration(hintText: 'مثلاً پسرعمو، عروس، پدرخوانده')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('ثبت')),
          ],
        ),
      );
      controller.dispose();
      if (custom != null && custom.isNotEmpty) await _set(c, custom);
      return;
    }
    await _set(c, selected);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.contacts, builder: (context, _) {
      final confirmed = widget.contacts.contacts.where((c) => relations.containsKey(c.key)).toList();
      final proposed = widget.contacts.contacts.where((c) => !relations.containsKey(c.key) &&
          !excluded.contains(c.key) && FamilyRelations.suggest(c.name) != null).toList();
      return Scaffold(
        appBar: AppBar(title: const Text('خانواده'), actions: [
          IconButton(tooltip: 'نمایش پیشنهادها', icon: Icon(showSuggestions
              ? Icons.manage_search : Icons.person_search_outlined),
            onPressed: () => setState(() => showSuggestions = !showSuggestions)),
        ]),
        body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
            Card(child: ListTile(
              leading: const Icon(Icons.family_restroom_rounded),
              title: const Text('خانواده من'),
              subtitle: const Text('دسته‌بندی‌ها خصوصی و فقط روی همین گوشی ذخیره می‌شوند. '
                  'نام مخاطب صرفاً برای پیشنهاد بررسی می‌شود؛ تأیید با شماست.'),
            )),
            Padding(padding: const EdgeInsets.all(12),
              child: Text('اعضای تأییدشده (${confirmed.length})',
                style: Theme.of(context).textTheme.titleMedium)),
            for (final relation in [
              ...FamilyRelations.labels.where((label) => confirmed.any((c) => relations[c.key] == label)),
              ...relations.values.where((r) => !FamilyRelations.labels.contains(r)).toSet(),
            ]) ...[
              Padding(padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                child: Text(relation, style: Theme.of(context).textTheme.titleSmall)),
              for (final c in confirmed.where((c) => relations[c.key] == relation))
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.favorite_outline)),
                  title: Text(c.displayName),
                  subtitle: Text(c.primaryPhone.isEmpty ? 'شماره ثبت نشده' : c.primaryPhone),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(c, null)),
            ],
            if (confirmed.isEmpty) const ListTile(title: Text('هنوز عضوی تأیید نشده است.')),
            if (showSuggestions) ...[
              Padding(padding: const EdgeInsets.all(12),
                child: Text('پیشنهادهای نام (${proposed.length})',
                  style: Theme.of(context).textTheme.titleMedium)),
              for (final c in proposed) ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(c.displayName),
                subtitle: Text('پیشنهاد: ${FamilyRelations.suggest(c.name)}'),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () => _edit(c, FamilyRelations.suggest(c.name))),
            ],
            const Padding(padding: EdgeInsets.fromLTRB(12, 18, 12, 6),
              child: Text('افزودن دستی از تمام مخاطبین')),
            for (final c in widget.contacts.contacts.where(
                (c) => !relations.containsKey(c.key) &&
                  (FamilyRelations.suggest(c.name) == null || !showSuggestions || excluded.contains(c.key))))
              ListTile(title: Text(c.displayName),
                trailing: const Icon(Icons.add_rounded), onTap: () => _edit(c, null)),
          ]),
      );
    });
  }
}
