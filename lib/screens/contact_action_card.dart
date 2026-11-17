import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../contacts/contacts_data.dart';
import '../sms_bridge.dart';

/// Local-only lookup. Keep a bounded cache so long conversation lists do not
/// repeatedly query Android's Contacts provider.
class ContactNameLookup {
  static final Map<String, Future<String?>> _cache = {};

  static Future<String?> resolve(String raw) {
    final key = phoneKey(raw);
    if (!SmsBridge.supported || !RegExp(r'^09[0-9]{9}$').hasMatch(key)) {
      return Future<String?>.value(null);
    }
    if (_cache.length >= 256) _cache.clear();
    return _cache.putIfAbsent(key, () async {
      try {
        final names = await SmsBridge.contactNames([key]);
        for (final entry in names.entries) {
          if (phoneKey(entry.key) == key && entry.value.trim().isNotEmpty) {
            return entry.value.trim();
          }
        }
      } catch (_) {
        // Reading contacts is optional and must never block SMS rendering.
      }
      return null;
    });
  }

  static void invalidate(String raw) => _cache.remove(phoneKey(raw));
}

Future<void> showContactActionCard(BuildContext context, String raw,
    {String? displayName, VoidCallback? onMessage}) async {
  final number = phoneKey(raw);
  if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(number)) return;
  var known = (displayName ?? '').trim();
  if (known.isEmpty || known == raw || known == number) {
    known = await ContactNameLookup.resolve(number) ?? '';
  }
  if (!context.mounted) return;
  final scheme = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.viewInsetsOf(sheet).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF087F81), Color(0xFF07585F),
            ], begin: Alignment.topRight, end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            CircleAvatar(
              radius: 28, backgroundColor: const Color(0x33FFFFFF),
              child: Icon(known.isEmpty ? Icons.person_outline_rounded : Icons.person_rounded,
                color: Colors.white, size: 30)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(known.isEmpty ? number : known, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 19, color: Colors.white)),
              if (known.isNotEmpty)
                Text(number, textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Color(0xFFE5F3EE), fontSize: 13)),
            ])),
            const Icon(Icons.contact_phone_rounded, color: Colors.white70),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _ContactButton(
            icon: Icons.sms_rounded, text: 'پیام',
            onTap: () {
              Navigator.pop(sheet);
              if (onMessage != null) {
                onMessage();
              } else {
                launchUrl(Uri(scheme: 'sms', path: number));
              }
            })),
          const SizedBox(width: 8),
          Expanded(child: _ContactButton(
            icon: Icons.call_rounded, text: 'تماس',
            onTap: () {
              Navigator.pop(sheet);
              launchUrl(Uri(scheme: 'tel', path: number));
            })),
          const SizedBox(width: 8),
          Expanded(child: _ContactButton(
            icon: Icons.badge_outlined, text: 'اطلاعات',
            onTap: () {
              Navigator.pop(sheet);
              _showContactDetails(context, number, known);
            })),
        ]),
        const SizedBox(height: 14),
        ListTile(
          tileColor: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: const Icon(Icons.copy_rounded),
          title: const Text('کپی شماره'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: number));
            Navigator.pop(sheet);
          }),
        if (known.isEmpty) ...[
          const SizedBox(height: 8),
          ListTile(
            tileColor: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: const Icon(Icons.person_add_alt_rounded),
            title: const Text('ذخیره در مخاطبین'),
            onTap: () {
              Navigator.pop(sheet);
              _saveContact(context, number);
            }),
        ],
      ]),
    ),
  );
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _ContactButton({required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
          child: Column(children: [
            Icon(icon, color: scheme.onPrimaryContainer),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer)),
          ]),
        ),
      ),
    );
  }
}

Future<PhoneContact?> _contactForNumber(String number) async {
  if (!ContactsBridge.supported) return null;
  try {
    var permission = await ContactsBridge.permissions();
    if (permission['read'] != true) {
      await ContactsBridge.requestPermissions();
      permission = await ContactsBridge.permissions();
    }
    if (permission['read'] != true) return null;
    for (final contact in await ContactsBridge.list()) {
      if (contact.phones.any((p) => phoneKey(p.value) == phoneKey(number))) {
        return contact;
      }
    }
  } catch (_) {
    // Some OEM contact providers may not expose all columns.
  }
  return null;
}

Future<void> _showContactDetails(
    BuildContext context, String number, String known) async {
  final details = _contactForNumber(number);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) => FutureBuilder<PhoneContact?>(
      future: details,
      builder: (ctx, snap) {
        final c = snap.data;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.account_circle_rounded, size: 68,
              color: Theme.of(sheet).colorScheme.primary),
            const SizedBox(height: 8),
            Text(c?.displayName ?? (known.isEmpty ? number : known),
              textAlign: TextAlign.center,
              style: Theme.of(sheet).textTheme.titleLarge),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
            else ...[
              const SizedBox(height: 10),
              if (c == null)
                ListTile(leading: const Icon(Icons.phone_outlined),
                  title: Text(number, textDirection: TextDirection.ltr),
                  subtitle: const Text('اطلاعات دیگری یافت نشد یا مجوز مخاطبین فعال نیست.')),
              for (final p in c?.phones ?? const <LabeledValue>[])
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(p.value, textDirection: TextDirection.ltr),
                  subtitle: Text(phoneTypeNames[p.type] ?? 'شماره'),
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: phoneKey(p.value)))),
              for (final e in c?.emails ?? const <LabeledValue>[])
                ListTile(leading: const Icon(Icons.email_outlined),
                  title: SelectableText(e.value)),
              if (c != null && c.org.isNotEmpty)
                ListTile(leading: const Icon(Icons.business_outlined),
                  title: Text(c.org), subtitle: Text(c.title)),
              if (c != null && c.note.isNotEmpty)
                Padding(padding: const EdgeInsets.all(12), child: SelectableText(c.note)),
            ],
          ]),
        );
      },
    ),
  );
}

Future<void> _saveContact(BuildContext context, String number) async {
  final input = TextEditingController();
  try {
    final label = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('مخاطب جدید'),
        content: TextField(
          controller: input, maxLength: 70,
          decoration: InputDecoration(labelText: 'نام مخاطب', helperText: number)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialog, input.text.trim()),
            child: const Text('ذخیره')),
        ],
      ),
    );
    if (label == null || label.isEmpty || !context.mounted) return;
    var access = await ContactsBridge.permissions();
    if (access['write'] != true) {
      await ContactsBridge.requestPermissions();
      access = await ContactsBridge.permissions();
    }
    if (access['write'] != true) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اجازه ذخیره مخاطب در تنظیمات گوشی فعال نیست.')));
      return;
    }
    await ContactsBridge.save(name: label, phones: [LabeledValue(number)]);
    ContactNameLookup.invalidate(number);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('مخاطب ذخیره شد.')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ذخیره مخاطب انجام نشد.')));
  } finally {
    input.dispose();
  }
}
