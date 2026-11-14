import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../app_store.dart';
import '../csv_util.dart';
import '../jalali.dart';
import '../message_logic.dart';
import 'contact_detail_screen.dart';
import 'contact_store.dart';
import 'contacts_data.dart';
import 'contacts_screen.dart' show ContactAvatar;

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأیید'),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> _askName(BuildContext context, String title, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'نام گروه')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('ذخیره'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// One group, or null. Offers to create a new one.
Future<ContactGroup?> pickGroup(BuildContext context, ContactStore contacts, {String title = 'انتخاب گروه'}) =>
    showModalBottomSheet<ContactGroup>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
          for (final g in contacts.groups)
            ListTile(
              leading: CircleAvatar(radius: 10, backgroundColor: Color(g.color)),
              title: Text(g.name),
              trailing: Text(Jalali.digits(contacts.countIn(g.id))),
              onTap: () => Navigator.pop(ctx, g),
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('گروه جدید'),
            onTap: () async {
              final name = await _askName(ctx, 'گروه جدید');
              if (name == null || name.isEmpty) return;
              final g = await contacts.createGroup(name, groupColors[contacts.groups.length % groupColors.length]);
              if (ctx.mounted) Navigator.pop(ctx, g);
            },
          ),
        ]),
      ),
    );

/// Multi-select of groups; null when cancelled.
Future<Set<String>?> pickGroups(BuildContext context, ContactStore contacts, Set<String> initial) {
  final chosen = {...initial};
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final g in contacts.groups)
            CheckboxListTile(
              secondary: CircleAvatar(radius: 10, backgroundColor: Color(g.color)),
              title: Text(g.name),
              value: chosen.contains(g.id),
              onChanged: (v) => set(() => v == true ? chosen.add(g.id) : chosen.remove(g.id)),
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('گروه جدید'),
            onTap: () async {
              final name = await _askName(ctx, 'گروه جدید');
              if (name == null || name.isEmpty) return;
              final g = await contacts.createGroup(name, groupColors[contacts.groups.length % groupColors.length]);
              set(() => chosen.add(g.id));
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(onPressed: () => Navigator.pop(ctx, chosen), child: const Text('تأیید')),
          ),
        ]),
      ),
    ),
  );
}

Future<void> editContactGroups(BuildContext context, ContactStore contacts, PhoneContact c) async {
  final picked = await pickGroups(context, contacts, {...?contacts.members[c.key]});
  if (picked != null) await contacts.setGroups(c, picked);
}

String _stamp() {
  final now = DateTime.now();
  final j = Jalali.fromGregorian(now.year, now.month, now.day);
  return '${j[0]}-${j[1].toString().padLeft(2, '0')}-${j[2].toString().padLeft(2, '0')}';
}

/// Lets the user choose Excel or VCF, then saves through Android's "save as" screen.
Future<void> exportContacts(BuildContext context, ContactStore contacts, List<PhoneContact> list) async {
  if (list.isEmpty) return;
  final format = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('خروجی ${Jalali.digits(list.length)} مخاطب', style: Theme.of(ctx).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.table_view_rounded, color: Color(0xFF1D6F42)),
          title: const Text('اکسل (xlsx)'),
          subtitle: const Text('قابل ویرایش در Excel و Google Sheets؛ همراه با گروه و تولد'),
          onTap: () => Navigator.pop(ctx, 'xlsx'),
        ),
        ListTile(
          leading: const Icon(Icons.contact_page_outlined, color: Color(0xFF3A7CA5)),
          title: const Text('vCard (vcf)'),
          subtitle: const Text('برای انتقال به گوشی دیگر یا Gmail و iCloud'),
          onTap: () => Navigator.pop(ctx, 'vcf'),
        ),
        ListTile(
          leading: const Icon(Icons.grid_on_rounded),
          title: const Text('CSV'),
          onTap: () => Navigator.pop(ctx, 'csv'),
        ),
      ]),
    ),
  );
  if (format == null) return;
  final base = list.length == 1 ? list.first.displayName : 'مخاطبین-پیامیار-${_stamp()}';
  final groups = contacts.groupNamesByKey;
  bool ok;
  if (format == 'xlsx') {
    final bytes = await ContactsBridge.xlsxWrite(contactsToRows(list, groups));
    ok = await ContactsBridge.saveFile('$base.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', bytes);
  } else if (format == 'csv') {
    ok = await ContactsBridge.saveFile('$base.csv', 'text/csv', csvBytes(contactsToRows(list, groups)));
  } else {
    ok = await ContactsBridge.saveFile('$base.vcf', 'text/x-vcard', Uint8List.fromList(utf8.encode(toVcf(list, groupsOf: groups))));
  }
  if (context.mounted && ok) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل ذخیره شد.')));
  }
}

Future<void> saveSampleExcel(BuildContext context, {void Function(String)? onNotice}) async {
  final bytes = await ContactsBridge.xlsxWrite([for (final r in sampleRows) List<String>.of(r)]);
  final ok = await ContactsBridge.saveFile('نمونه-ورود-مخاطبین-پیامیار.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', bytes);
  if (ok) onNotice?.call('فایل نمونه ذخیره شد؛ آن را پر کنید و از «ورود از فایل» وارد کنید.');
}

/// Picks a VCF, Excel or CSV file, shows a preview and writes the new contacts.
Future<void> importContacts(BuildContext context, ContactStore contacts, {void Function(String)? onNotice}) async {
  final file = await ContactsBridge.openFile();
  if (file == null || !context.mounted) return;
  final lower = file.name.toLowerCase();
  List<ContactDraft> drafts;
  final isVcf = lower.endsWith('.vcf') || utf8.decode(file.bytes.take(64).toList(), allowMalformed: true).contains('BEGIN:VCARD');
  try {
    if (isVcf) {
      drafts = parseVcf(utf8.decode(file.bytes, allowMalformed: true));
    } else if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      drafts = rowsToDrafts(parseCsv(utf8.decode(file.bytes, allowMalformed: true)));
    } else {
      drafts = rowsToDrafts(await ContactsBridge.xlsxRead(file.bytes));
    }
  } catch (e) {
    onNotice?.call('خواندن فایل انجام نشد: $e');
    return;
  }
  if (!context.mounted) return;
  if (drafts.isEmpty) {
    onNotice?.call('مخاطبی در این فایل پیدا نشد. ستون‌ها را با فایل نمونه مقایسه کنید.');
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ImportPreview(contacts: contacts, drafts: drafts, vcf: isVcf ? file.bytes : null, onNotice: onNotice)));
}

class _ImportPreview extends StatefulWidget {
  final ContactStore contacts;
  final List<ContactDraft> drafts;
  final Uint8List? vcf;
  final void Function(String)? onNotice;
  const _ImportPreview({required this.contacts, required this.drafts, this.vcf, this.onNotice});

  @override
  State<_ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<_ImportPreview> {
  bool skipDuplicates = true;
  bool running = false;
  int done = 0;

  bool _exists(ContactDraft d) => d.phones.any((p) => widget.contacts.byPhone(p.value) != null);

  Future<void> _run() async {
    if (!await widget.contacts.ensureWrite()) {
      widget.onNotice?.call('برای ورود مخاطبین، اجازه نوشتن در دفترچه تلفن لازم است.');
      return;
    }
    setState(() {
      running = true;
      done = 0;
    });
    final created = <int, List<String>>{};
    var added = 0;
    for (final d in widget.drafts) {
      if (!mounted) return;
      if (skipDuplicates && _exists(d)) {
        setState(() => done++);
        continue;
      }
      try {
        final id = await ContactsBridge.save(name: d.name, phones: d.phones, emails: d.emails, org: d.org,
            title: d.title, note: d.note, birthday: d.birthday);
        if (id > 0) {
          added++;
          if (d.groups.isNotEmpty) created[id] = d.groups;
        }
      } catch (_) {
        // One bad row must not stop the rest.
      }
      if (mounted) setState(() => done++);
    }
    await widget.contacts.load();
    for (final e in created.entries) {
      final c = widget.contacts.byId(e.key);
      if (c == null) continue;
      final ids = <String>{};
      for (final name in e.value) {
        final id = await widget.contacts.groupIdByName(name);
        if (id != null) ids.add(id);
      }
      await widget.contacts.setGroups(c, ids);
    }
    final shown = Jalali.digits(added);
    widget.onNotice?.call('$shown مخاطب وارد شد.');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dup = widget.drafts.where(_exists).length;
    final total = widget.drafts.length;
    return Scaffold(
      appBar: AppBar(title: const Text('پیش‌نمایش ورود مخاطبین')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: .4), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${Jalali.digits(total)} مخاطب در فایل • ${Jalali.digits(dup)} شماره از قبل در گوشی هست',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('رد کردن مخاطبانی که شماره‌شان از قبل هست'),
                value: skipDuplicates,
                onChanged: running ? null : (v) => setState(() => skipDuplicates = v),
              ),
              if (running) ...[
                LinearProgressIndicator(value: total == 0 ? null : done / total),
                const SizedBox(height: 6),
                Text('${Jalali.digits(done)} از ${Jalali.digits(total)}'),
              ],
            ]),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: total,
            itemBuilder: (context, i) {
              final d = widget.drafts[i];
              final exists = _exists(d);
              return ListTile(
                leading: CircleAvatar(child: Text(d.name.trim().isEmpty ? '#' : String.fromCharCode(d.name.trim().runes.first))),
                title: Text(d.name.isEmpty ? (d.phones.isNotEmpty ? d.phones.first.value : 'بی‌نام') : d.name),
                subtitle: Text([
                  ...d.phones.map((p) => p.value),
                  ...d.emails.map((e) => e.value),
                  if (d.groups.isNotEmpty) 'گروه: ${d.groups.join('، ')}',
                ].join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: exists ? Icon(Icons.copy_rounded, color: scheme.error, size: 18) : null,
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              if (widget.vcf != null)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: running ? null : () => ContactsBridge.importWithSystem(widget.vcf!),
                    child: const Text('با برنامه مخاطبین گوشی'),
                  ),
                ),
              if (widget.vcf != null) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: running ? null : _run,
                  icon: const Icon(Icons.download_done_rounded),
                  label: const Text('ورود به پیامیار'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Duplicates, incomplete entries, untidy numbers and contacts you have not texted in a long time.
class ContactToolsScreen extends StatelessWidget {
  final AppStore store;
  final ContactStore contacts;
  const ContactToolsScreen({super.key, required this.store, required this.contacts});

  void _open(BuildContext context, PhoneContact c) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ContactDetailScreen(store: store, contacts: contacts, contactId: c.id)));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: ListenableBuilder(
        listenable: contacts,
        builder: (context, child) {
          final dups = contacts.duplicates;
          final names = contacts.similarNames;
          final incomplete = contacts.incomplete;
          final untidy = contacts.untidy;
          final forgotten = _forgotten();
          return Scaffold(
            appBar: AppBar(
              title: const Text('پاک‌سازی مخاطبین'),
              bottom: TabBar(isScrollable: true, tabs: [
                Tab(text: 'تکراری ${Jalali.digits(dups.length)}'),
                Tab(text: 'هم‌نام ${Jalali.digits(names.length)}'),
                Tab(text: 'ناقص ${Jalali.digits(incomplete.length)}'),
                Tab(text: 'شماره نامرتب ${Jalali.digits(untidy.length)}'),
                Tab(text: 'فراموش‌شده ${Jalali.digits(forgotten.length)}'),
              ]),
            ),
            body: TabBarView(children: [
              _dupList(context, dups),
              _nameReviewList(context, names),
              _simpleList(context, incomplete, 'همه مخاطبین کامل‌اند.', _problem),
              _untidyList(context, untidy),
              _simpleList(context, forgotten, 'با همه مخاطبین پرکار در ۶ ماه اخیر پیامک داشته‌اید.', (c) => 'بیش از ۶ ماه بدون پیامک'),
            ]),
          );
        },
      ),
    );
  }

  String _problem(PhoneContact c) {
    if (c.name.trim().isEmpty || RegExp(r'^[\d\s+()-]+$').hasMatch(c.name.trim())) return 'بدون نام';
    if (c.phones.isEmpty && c.emails.isEmpty) return 'بدون شماره و ایمیل';
    return 'شماره نامعتبر';
  }

  /// People you once texted (≥3 messages) but not in the last 180 days.
  List<PhoneContact> _forgotten() {
    final limit = DateTime.now().subtract(const Duration(days: 180));
    final out = <PhoneContact>[];
    for (final c in contacts.contacts) {
      var count = 0;
      DateTime? last;
      for (final p in c.phones) {
        final conv = store.conversationFor(p.value);
        if (conv == null || store.categoryOf(conv) != MessageCategory.personal) continue;
        count += conv.count;
        final d = conv.latest.date;
        if (last == null || d.isAfter(last)) last = d;
      }
      if (count >= 3 && last != null && last.isBefore(limit)) out.add(c);
    }
    return out;
  }

  Widget _empty(String text) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(text, textAlign: TextAlign.center)));

  Widget _simpleList(BuildContext context, List<PhoneContact> list, String empty, String Function(PhoneContact) why) {
    if (list.isEmpty) return _empty(empty);
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) => ListTile(
        leading: ContactAvatar(contacts: contacts, contact: list[i]),
        title: Text(list[i].displayName),
        subtitle: Text(why(list[i])),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => _open(context, list[i]),
      ),
    );
  }

  Widget _untidyList(BuildContext context, List<PhoneContact> list) {
    if (list.isEmpty) return _empty('همه شماره‌ها مرتب‌اند.');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: () async {
            final count = Jalali.digits(list.length);
            if (!await confirm(context, 'یکدست‌سازی $count مخاطب',
                'شماره‌ها به شکل استاندارد ۰۹xxxxxxxxx ذخیره می‌شوند (ارقام فارسی، فاصله و +۹۸ اصلاح می‌شود).')) {
              return;
            }
            for (final c in list) {
              await contacts.tidy(c);
            }
            await contacts.load();
            store.onNotice?.call('شماره‌ها یکدست شدند.');
          },
          icon: const Icon(Icons.auto_fix_high_rounded),
          label: const Text('یکدست‌سازی همه'),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final c = list[i];
            final bad = c.phones.where((p) => isUntidy(p.value)).toList();
            return ListTile(
              leading: ContactAvatar(contacts: contacts, contact: c),
              title: Text(c.displayName),
              subtitle: Text(bad.map((p) => '${p.value} ← ${phoneKey(p.value)}').join('\n'), textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right),
              onTap: () => _open(context, c),
            );
          },
        ),
      ),
    ]);
  }

  Widget _nameReviewList(BuildContext context, List<List<PhoneContact>> groups) {
    if (groups.isEmpty) return _empty('نام تکراری نیازمند بررسی پیدا نشد.');
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('این افراد فقط نام یکسان دارند. ادغام خودکار آن‌ها غیرفعال است؛ '
            'ابتدا شماره و هویت هر مخاطب را بررسی کنید و فقط در صورت اطمینان از '
            'بخش انتخاب چندتایی، ادغام دستی انجام دهید.'),
      )),
      for (final group in groups)
        Card(child: Column(children: [
          for (final c in group)
            ListTile(
              leading: ContactAvatar(contacts: contacts, contact: c, radius: 18),
              title: Text(c.displayName),
              subtitle: Text(c.phones.map((p) => p.value).join(' • '),
                  textDirection: TextDirection.ltr, textAlign: TextAlign.right),
              onTap: () => _open(context, c),
            ),
        ])),
    ]);
  }

  Widget _dupList(BuildContext context, List<List<PhoneContact>> clusters) {
    if (clusters.isEmpty) return _empty('مخاطب تکراری پیدا نشد.');
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: clusters.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton.icon(
              onPressed: () async {
                final n = Jalali.digits(clusters.length);
                if (!await confirm(context, 'ادغام همه ($n دسته)',
                    'هر دسته تکراری به یک مخاطب با همه شماره‌ها، ایمیل‌ها و گروه‌ها تبدیل می‌شود.')) {
                  return;
                }
                final merged = await contacts.mergeAll();
                store.onNotice?.call('${Jalali.digits(merged)} دسته تکراری ادغام شد.');
              },
              icon: const Icon(Icons.merge_type_rounded),
              label: const Text('ادغام همه تکراری‌ها با یک لمس'),
            ),
          );
        }
        final group = clusters[index - 1];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              for (final c in group)
                ListTile(
                  dense: true,
                  leading: ContactAvatar(contacts: contacts, contact: c, radius: 18),
                  title: Text(c.displayName),
                  subtitle: Text(c.phones.map((p) => p.value).join(' • '), textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                  trailing: IconButton(
                    tooltip: 'حذف این مورد',
                    icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                    onPressed: () async {
                      if (await confirm(context, 'حذف مخاطب', '«${c.displayName}» از گوشی حذف شود؟')) await contacts.remove([c]);
                    },
                  ),
                  onTap: () => _open(context, c),
                ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () async {
                    final ok = await contacts.merge(group);
                    store.onNotice?.call(ok ? 'مخاطبان ادغام شدند.' : 'ادغام انجام نشد.');
                  },
                  icon: const Icon(Icons.merge_rounded),
                  label: const Text('ادغام'),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Create, rename, recolour and delete PayamYar contact groups.
class GroupsManagerScreen extends StatelessWidget {
  final ContactStore contacts;
  const GroupsManagerScreen({super.key, required this.contacts});

  Future<void> _edit(BuildContext context, [ContactGroup? g]) async {
    final name = await _askName(context, g == null ? 'گروه جدید' : 'تغییر نام گروه', initial: g?.name ?? '');
    if (name == null || name.isEmpty || !context.mounted) return;
    final color = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رنگ گروه'),
        content: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in groupColors)
            InkWell(onTap: () => Navigator.pop(ctx, c), child: CircleAvatar(radius: 20, backgroundColor: Color(c))),
        ]),
      ),
    );
    final chosen = color ?? g?.color ?? groupColors.first;
    if (g == null) {
      await contacts.createGroup(name, chosen);
    } else {
      await contacts.renameGroup(g.id, name, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: contacts,
      builder: (context, child) => Scaffold(
        appBar: AppBar(title: const Text('گروه‌های مخاطبین')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('گروه جدید'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
          for (final g in contacts.groups)
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Color(g.color), child: const Icon(Icons.folder_shared_rounded, color: Colors.white)),
                title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${Jalali.digits(contacts.countIn(g.id))} مخاطب'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') await _edit(context, g);
                    if (v == 'delete' && context.mounted &&
                        await confirm(context, 'حذف گروه', 'گروه «${g.name}» حذف می‌شود؛ مخاطبان آن حذف نمی‌شوند.')) {
                      await contacts.deleteGroup(g.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تغییر نام و رنگ')),
                    PopupMenuItem(value: 'delete', child: Text('حذف گروه')),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
