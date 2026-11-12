import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../jalali.dart';
import 'contact_store.dart';
import 'contacts_data.dart';
import 'contacts_tools.dart';

/// Add or edit a phone-book contact: photo, name, several numbers and e-mails, company, birthday,
/// note and PayamYar groups. Pops with the saved contact id.
class ContactEditScreen extends StatefulWidget {
  final ContactStore contacts;
  final PhoneContact? initial;
  final ContactDraft? draft;
  const ContactEditScreen({super.key, required this.contacts, this.initial, this.draft});

  @override
  State<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _Field {
  final TextEditingController text;
  int type;
  _Field(String value, this.type) : text = TextEditingController(text: value);
}

class _ContactEditScreenState extends State<ContactEditScreen> {
  late final name = TextEditingController(text: widget.initial?.name ?? widget.draft?.name ?? '');
  late final org = TextEditingController(text: widget.initial?.org ?? widget.draft?.org ?? '');
  late final title = TextEditingController(text: widget.initial?.title ?? widget.draft?.title ?? '');
  late final note = TextEditingController(text: widget.initial?.note ?? widget.draft?.note ?? '');
  late final List<_Field> phones = [
    for (final p in widget.initial?.phones ?? widget.draft?.phones ?? const <LabeledValue>[]) _Field(p.value, p.type),
  ];
  late final List<_Field> emails = [
    for (final e in widget.initial?.emails ?? widget.draft?.emails ?? const <LabeledValue>[]) _Field(e.value, e.type),
  ];
  late List<int>? birthday = PhoneContact(id: 0, name: '', birthday: widget.initial?.birthday ?? widget.draft?.birthday ?? '').jalaliBirthday;
  late Set<String> groupIds = widget.initial == null ? <String>{} : {...?widget.contacts.members[widget.initial!.key]};
  Uint8List? photo;
  Uint8List? currentPhoto;
  bool removePhoto = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (phones.isEmpty) phones.add(_Field('', 2));
    final c = widget.initial;
    if (c != null && c.hasPhoto) {
      widget.contacts.photo(c).then((v) {
        if (mounted && v is Uint8List) setState(() => currentPhoto = v);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [name, org, title, note, ...phones.map((p) => p.text), ...emails.map((e) => e.text)]) {
      c.dispose();
    }
    super.dispose();
  }

  String _birthdayValue() {
    final b = birthday;
    if (b == null) return '';
    if (b[0] == 0) {
      final g = Jalali.toGregorian(1400, b[1], b[2]);
      return '--${g[1].toString().padLeft(2, '0')}-${g[2].toString().padLeft(2, '0')}';
    }
    final g = Jalali.toGregorian(b[0], b[1], b[2]);
    return '${g[0]}-${g[1].toString().padLeft(2, '0')}-${g[2].toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final phoneList = [for (final p in phones) if (p.text.text.trim().isNotEmpty) LabeledValue(p.text.text.trim(), type: p.type)];
    final emailList = [for (final e in emails) if (e.text.text.trim().isNotEmpty) LabeledValue(e.text.text.trim(), type: e.type)];
    if (name.text.trim().isEmpty && phoneList.isEmpty && emailList.isEmpty) {
      _snack('نام یا شماره مخاطب را وارد کنید.');
      return;
    }
    final bad = phoneList.where((p) => !isValidPhone(p.value)).toList();
    if (bad.isNotEmpty) {
      _snack('شماره «${bad.first.value}» معتبر نیست.');
      return;
    }
    if (!await widget.contacts.ensureWrite()) {
      _snack('برای ذخیره، اجازه نوشتن در مخاطبین را بدهید.');
      return;
    }
    setState(() => saving = true);
    try {
      final id = await ContactsBridge.save(
        id: widget.initial?.id ?? 0,
        name: name.text.trim(),
        phones: phoneList,
        emails: emailList,
        org: org.text.trim(),
        title: title.text.trim(),
        note: note.text.trim(),
        birthday: _birthdayValue(),
        clearBirthday: birthday == null && (widget.initial?.birthday.isNotEmpty ?? false),
        photo: photo,
        removePhoto: removePhoto,
      );
      if (photo != null || removePhoto) widget.contacts.forgetPhoto(id);
      await widget.contacts.load();
      final saved = widget.contacts.byId(id);
      if (saved != null) await widget.contacts.setGroups(saved, groupIds);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) setState(() => saving = false);
      _snack('ذخیره انجام نشد: $e');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _photoMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('انتخاب عکس از گالری'),
              onTap: () => Navigator.pop(ctx, 'pick')),
          if (currentPhoto != null || photo != null)
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('حذف عکس'),
                onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (choice == 'pick') {
      final bytes = await ContactsBridge.pickPhoto();
      if (bytes != null && mounted) {
        setState(() {
          photo = bytes;
          removePhoto = false;
        });
      }
    } else if (choice == 'remove') {
      setState(() {
        photo = null;
        currentPhoto = null;
        removePhoto = true;
      });
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final jy = Jalali.fromGregorian(now.year, now.month, now.day)[0];
    var y = birthday?[0] ?? 0, m = birthday?[1] ?? 1, d = birthday?[2] ?? 1;
    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('تاریخ تولد (شمسی)'),
          content: Row(children: [
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: d.clamp(1, m <= 6 ? 31 : 30).toInt(),
                items: [for (var i = 1; i <= (m <= 6 ? 31 : 30); i++) DropdownMenuItem(value: i, child: Text(Jalali.digits(i)))],
                onChanged: (v) => set(() => d = v ?? d),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: DropdownButton<int>(
                isExpanded: true,
                value: m,
                items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(Jalali.months[i - 1]))],
                onChanged: (v) => set(() {
                  m = v ?? m;
                  d = d.clamp(1, m <= 6 ? 31 : 30).toInt();
                }),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: y,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('سال؟')),
                  for (var i = jy; i >= jy - 100; i--) DropdownMenuItem(value: i, child: Text(Jalali.digits(i))),
                ],
                onChanged: (v) => set(() => y = v ?? 0),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, [y, m, d]),
              child: const Text('تأیید'),
            ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => birthday = result);
  }

  Widget _list(String label, IconData icon, List<_Field> fields, Map<int, String> types, TextInputType keyboard) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(children: [
          for (var i = 0; i < fields.length; i++)
            Row(children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: fields[i].text,
                  keyboardType: keyboard,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: label, filled: false),
                ),
              ),
              DropdownButton<int>(
                value: types.containsKey(fields[i].type) ? fields[i].type : types.keys.first,
                underline: const SizedBox.shrink(),
                items: [for (final e in types.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))],
                onChanged: (v) => setState(() => fields[i].type = v ?? fields[i].type),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed: () => setState(() => fields.removeAt(i).text.dispose()),
              ),
            ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => fields.add(_Field('', types.keys.first))),
              icon: const Icon(Icons.add_rounded),
              label: Text('افزودن $label'),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = photo ?? currentPhoto;
    final b = birthday;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'مخاطب جدید' : 'ویرایش مخاطب'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: saving ? null : _save,
              child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ذخیره'),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Center(
          child: GestureDetector(
            onTap: _photoMenu,
            child: Stack(children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: shown == null ? null : MemoryImage(shown),
                child: shown == null ? Icon(Icons.person_rounded, size: 56, color: scheme.onPrimaryContainer) : null,
              ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: CircleAvatar(radius: 18, backgroundColor: scheme.primary,
                    child: Icon(Icons.photo_camera_rounded, size: 18, color: scheme.onPrimary)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'نام و نام خانوادگی', prefixIcon: Icon(Icons.person_outline_rounded))),
        const SizedBox(height: 12),
        _list('شماره', Icons.phone_outlined, phones, {for (final e in phoneTypeNames.entries) if (e.key != 0) e.key: e.value}, TextInputType.phone),
        _list('ایمیل', Icons.alternate_email_rounded, emails, emailTypeNames, TextInputType.emailAddress),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: org, decoration: const InputDecoration(labelText: 'شرکت / سازمان'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: title, decoration: const InputDecoration(labelText: 'سمت'))),
        ]),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cake_outlined, color: Color(0xFFB4537A)),
            title: Text(b == null
                ? 'تاریخ تولد'
                : '${Jalali.digits(b[2])} ${Jalali.months[b[1] - 1]}${b[0] > 0 ? ' ${Jalali.digits(b[0])}' : ''}'),
            trailing: b == null
                ? const Icon(Icons.add_rounded)
                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => birthday = null)),
            onTap: _pickBirthday,
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.folder_shared_outlined, color: scheme.primary),
            title: const Text('گروه‌ها'),
            subtitle: Text(groupIds.isEmpty
                ? 'بدون گروه'
                : [for (final id in groupIds) widget.contacts.group(id)?.name ?? ''].where((s) => s.isNotEmpty).join('، ')),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () async {
              final picked = await pickGroups(context, widget.contacts, groupIds);
              if (picked != null) setState(() => groupIds = picked);
            },
          ),
        ),
        const SizedBox(height: 8),
        TextField(controller: note, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'یادداشت')),
      ]),
    );
  }
}
