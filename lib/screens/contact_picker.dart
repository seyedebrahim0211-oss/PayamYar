import 'package:flutter/material.dart';
import '../sms_bridge.dart';

/// In-app contact list, without launching Android's external contact picker.
Future<Set<String>?> showContactPicker(
  BuildContext context, {
  required List<Map<String, String>> contacts,
  required Set<String> selected,
  int maxSelection = 500,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ContactPicker(
      contacts: contacts,
      initial: selected,
      limit: maxSelection,
    ),
  );
}

class _ContactPicker extends StatefulWidget {
  final List<Map<String, String>> contacts;
  final Set<String> initial;
  final int limit;
  const _ContactPicker({
    required this.contacts,
    required this.initial,
    required this.limit,
  });

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  final search = TextEditingController();
  late final Set<String> selected = {...widget.initial};

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<Map<String, String>> get filtered {
    final query = SmsBridge.normalizeNumber(search.text.trim()).toLowerCase();
    if (query.isEmpty) return widget.contacts;
    return widget.contacts.where((c) =>
      (c['name'] ?? '').toLowerCase().contains(query) ||
      SmsBridge.normalizeNumber(c['number'] ?? '').contains(query)).toList();
  }

  void _toggle(String number) {
    if (selected.contains(number)) {
      setState(() => selected.remove(number));
    } else if (selected.length < widget.limit) {
      setState(() => selected.add(number));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('در هر نوبت حداکثر ${widget.limit} گیرنده انتخاب کنید.'),
      ));
    }
  }

  void _allVisible(List<Map<String, String>> visible) {
    final numbers = visible.map((c) => c['number']!).toSet();
    final allPicked = numbers.isNotEmpty && numbers.every(selected.contains);
    setState(() {
      if (allPicked) {
        selected.removeAll(numbers);
      } else {
        for (final number in numbers) {
          if (selected.length >= widget.limit) break;
          selected.add(number);
        }
      }
    });
    if (!allPicked && numbers.any((n) => !selected.contains(n))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('حداکثر ${widget.limit} مخاطب انتخاب می‌شود؛ محدودیت‌های اپراتور ممکن است مستقل از این مقدار باشد.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = filtered;
    final allPicked = visible.isNotEmpty &&
        visible.every((c) => selected.contains(c['number']));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .83,
      child: Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(18, 2, 18, 8),
          child: Row(children: [
            const Icon(Icons.people_alt_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text('انتخاب مخاطبان',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            Text('${selected.length} انتخاب‌شده',
              style: TextStyle(fontSize: 12, color: colors.primary, fontWeight: FontWeight.bold)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: search,
            autofocus: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'جستجوی نام یا شماره',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.text.isEmpty ? null : IconButton(
                tooltip: 'پاک کردن جستجو',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(search.clear),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            TextButton.icon(
              onPressed: visible.isEmpty ? null : () => _allVisible(visible),
              icon: Icon(allPicked ? Icons.deselect_rounded : Icons.select_all_rounded),
              label: Text(allPicked ? 'لغو انتخاب همه' : 'انتخاب همه نتایج'),
            ),
            const Spacer(),
            Text('${visible.length} مخاطب',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: visible.isEmpty
          ? const Center(child: Text('مخاطبی پیدا نشد.'))
          : ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final c = visible[index];
                final name = c['name'] ?? '';
                final number = c['number'] ?? '';
                final checked = selected.contains(number);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (_) => _toggle(number),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: Text(name.isNotEmpty ? name.substring(0, 1) : '؟'),
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(number, textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right),
                );
              },
            )),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(selected),
            icon: const Icon(Icons.check_rounded),
            label: Text('تأیید ${selected.length} مخاطب'),
          ),
        )),
      ]),
    );
  }
}
