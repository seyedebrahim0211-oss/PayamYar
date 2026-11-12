import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../birthdays.dart';
import '../jalali.dart';
import '../screens/compose_screen.dart';
import '../screens/conversation_screen.dart';
import '../sms_bridge.dart';
import 'contact_edit_screen.dart';
import 'contact_store.dart';
import 'contacts_data.dart';
import 'contacts_screen.dart' show ContactAvatar;
import 'contacts_tools.dart';

/// One person's profile: numbers, e-mails, groups, SMS history and quick actions.
class ContactDetailScreen extends StatelessWidget {
  final AppStore store;
  final ContactStore contacts;
  final int contactId;
  const ContactDetailScreen({super.key, required this.store, required this.contacts, required this.contactId});

  void _notice(String t) => store.onNotice?.call(t);

  String _card(PhoneContact c) => [
        c.displayName,
        for (final p in c.phones) '${phoneTypeNames[p.type] ?? 'تلفن'}: ${p.value}',
        for (final e in c.emails) 'ایمیل: ${e.value}',
        if (c.org.isNotEmpty) [c.org, c.title].where((s) => s.isNotEmpty).join(' — '),
      ].join('\n');

  Future<void> _addBirthday(BuildContext context, PhoneContact c) async {
    final j = c.jalaliBirthday;
    if (j == null || c.primaryPhone.isEmpty) {
      _notice('ابتدا تاریخ تولد و شماره موبایل را در ویرایش مخاطب ثبت کنید.');
      return;
    }
    final b = BirthdayStore();
    await b.load();
    final number = phoneKey(c.primaryPhone);
    final existing = b.items.where((x) => phoneKey(x.number) == number).toList();
    await b.upsert(Birthday(
      id: existing.isEmpty ? BirthdayStore.newId() : existing.first.id,
      name: c.displayName,
      number: number,
      month: j[1],
      day: j[2],
      year: j[0],
    ));
    b.dispose();
    final name = c.displayName;
    _notice('تبریک خودکار تولد $name در تقویم تولد فعال شد.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([contacts, store]),
      builder: (context, child) {
        final c = contacts.byId(contactId);
        if (c == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('این مخاطب دیگر وجود ندارد.')));
        }
        final scheme = Theme.of(context).colorScheme;
        final groups = contacts.groupsOf(c);
        // SMS history across every number of this person.
        var count = 0;
        DateTime? last;
        String? convAddress;
        for (final p in c.phones) {
          final conv = store.conversationFor(p.value);
          if (conv == null) continue;
          count += conv.count;
          final d = conv.latest.date;
          if (last == null || d.isAfter(last)) {
            last = d;
            convAddress = conv.address;
          }
        }
        final jb = c.jalaliBirthday;
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: c.starred ? 'حذف از علاقه‌مندی‌ها' : 'افزودن به علاقه‌مندی‌ها',
                icon: Icon(c.starred ? Icons.star_rounded : Icons.star_border_rounded,
                    color: c.starred ? const Color(0xFFE0A526) : null),
                onPressed: () => contacts.toggleStar(c),
              ),
              IconButton(
                tooltip: 'ویرایش',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<int>(
                    builder: (_) => ContactEditScreen(contacts: contacts, initial: c))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'share':
                      await SmsBridge.shareText(_card(c), subject: c.displayName, title: 'ارسال کارت ویزیت');
                    case 'sms-card':
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => ComposeScreen(store: store, initialBody: _card(c))));
                    case 'vcf':
                      await exportContacts(context, contacts, [c]);
                    case 'copy':
                      await Clipboard.setData(ClipboardData(text: _card(c)));
                      _notice('اطلاعات مخاطب کپی شد.');
                    case 'block':
                      if (c.primaryPhone.isNotEmpty) await store.block(c.primaryPhone);
                    case 'system':
                      await ContactsBridge.openSystemEditor(c.id);
                    case 'delete':
                      if (await confirm(context, 'حذف مخاطب', 'این مخاطب از دفترچه تلفن گوشی حذف می‌شود.')) {
                        await contacts.remove([c]);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'share', child: Text('ارسال کارت ویزیت')),
                  PopupMenuItem(value: 'sms-card', child: Text('ارسال کارت ویزیت با پیامک')),
                  PopupMenuItem(value: 'vcf', child: Text('خروجی VCF یا اکسل')),
                  PopupMenuItem(value: 'copy', child: Text('کپی اطلاعات')),
                  PopupMenuItem(value: 'block', child: Text('مسدود کردن شماره')),
                  PopupMenuItem(value: 'system', child: Text('باز کردن در مخاطبین گوشی')),
                  PopupMenuItem(value: 'delete', child: Text('حذف مخاطب')),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            Center(child: ContactAvatar(contacts: contacts, contact: c, radius: 52)),
            const SizedBox(height: 12),
            Text(c.displayName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            if (c.org.isNotEmpty || c.title.isNotEmpty)
              Text([c.title, c.org].where((s) => s.isNotEmpty).join(' • '),
                  textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Action(icon: Icons.call_rounded, label: 'تماس', color: const Color(0xFF2E9E6A),
                  onTap: c.primaryPhone.isEmpty ? null : () => ContactsBridge.dial(c.primaryPhone)),
              _Action(icon: Icons.chat_rounded, label: 'پیامک', color: scheme.primary,
                  onTap: c.primaryPhone.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => ConversationScreen(store: store, address: convAddress ?? c.primaryPhone)))),
              _Action(icon: Icons.mail_rounded, label: 'ایمیل', color: const Color(0xFF3A7CA5),
                  onTap: c.emails.isEmpty ? null : () => ContactsBridge.email(c.emails.first.value)),
              _Action(icon: Icons.share_rounded, label: 'کارت', color: const Color(0xFFA17A37),
                  onTap: () => SmsBridge.shareText(_card(c), subject: c.displayName, title: 'ارسال کارت ویزیت')),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(child: _Fact(label: 'پیامک‌ها', value: Jalali.digits(count))),
                  Expanded(child: _Fact(label: 'آخرین پیامک', value: last == null ? '—' : Jalali.short(last))),
                  Expanded(child: _Fact(label: 'گروه‌ها', value: Jalali.digits(groups.length))),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            if (c.phones.isNotEmpty)
              Card(
                child: Column(children: [
                  for (final p in c.phones)
                    ListTile(
                      leading: Icon(Icons.phone_rounded, color: scheme.primary),
                      title: Text(Jalali.digits(p.value), textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                      subtitle: Text(phoneTypeNames[p.type] ?? (p.label.isEmpty ? 'تلفن' : p.label)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (isUntidy(p.value))
                          IconButton(
                            tooltip: 'یکدست‌سازی شماره',
                            icon: const Icon(Icons.auto_fix_high_rounded),
                            onPressed: () async {
                              await contacts.tidy(c);
                              await contacts.load();
                            },
                          ),
                        IconButton(tooltip: 'پیامک', icon: const Icon(Icons.sms_outlined), onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => ConversationScreen(store: store, address: p.value)))),
                        IconButton(tooltip: 'تماس', icon: const Icon(Icons.call_outlined), onPressed: () => ContactsBridge.dial(p.value)),
                      ]),
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: p.value));
                        _notice('شماره کپی شد.');
                      },
                    ),
                ]),
              ),
            if (c.emails.isNotEmpty)
              Card(
                child: Column(children: [
                  for (final e in c.emails)
                    ListTile(
                      leading: Icon(Icons.alternate_email_rounded, color: scheme.primary),
                      title: Text(e.value, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                      subtitle: Text(emailTypeNames[e.type] ?? 'ایمیل'),
                      onTap: () => ContactsBridge.email(e.value),
                    ),
                ]),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.folder_shared_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('گروه‌ها', style: TextStyle(fontWeight: FontWeight.w800))),
                    TextButton(
                      onPressed: () => editContactGroups(context, contacts, c),
                      child: const Text('ویرایش'),
                    ),
                  ]),
                  if (groups.isEmpty)
                    Text('در هیچ گروهی نیست.', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final g in groups)
                        Chip(
                          avatar: CircleAvatar(radius: 6, backgroundColor: Color(g.color)),
                          label: Text(g.name),
                        ),
                    ]),
                ]),
              ),
            ),
            if (jb != null || c.note.isNotEmpty)
              Card(
                child: Column(children: [
                  if (jb != null)
                    ListTile(
                      leading: const Icon(Icons.cake_outlined, color: Color(0xFFB4537A)),
                      title: Text('تولد: ${Jalali.digits(jb[2])} ${Jalali.months[jb[1] - 1]}${jb[0] > 0 ? ' ${Jalali.digits(jb[0])}' : ''}'),
                      trailing: TextButton(onPressed: () => _addBirthday(context, c), child: const Text('تبریک خودکار')),
                    ),
                  if (c.note.isNotEmpty)
                    ListTile(leading: Icon(Icons.sticky_note_2_outlined, color: scheme.primary), title: Text(c.note)),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _Action({required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: (enabled ? color : Colors.grey).withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: enabled ? color : Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: enabled ? null : Colors.grey)),
          ]),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}
