import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../screens/compose_screen.dart';
import '../sms_bridge.dart';
import 'contact_detail_screen.dart';
import 'contact_edit_screen.dart';
import 'contact_store.dart';
import 'contacts_data.dart';
import 'contacts_tools.dart';

/// Round contact picture: the phone-book photo, or a coloured initial.
class ContactAvatar extends StatelessWidget {
  final ContactStore contacts;
  final PhoneContact contact;
  final double radius;
  const ContactAvatar({super.key, required this.contacts, required this.contact, this.radius = 22});

  static const _palette = [0xFF087F81, 0xFF305F91, 0xFF75539A, 0xFF9F5369, 0xFF47765F, 0xFFA17A37, 0xFFC0583B, 0xFF3A7CA5];

  @override
  Widget build(BuildContext context) {
    final color = Color(_palette[contact.displayName.hashCode.abs() % _palette.length]);
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Color.lerp(color, Colors.white, .25)!, color],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(contact.initial,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * .8)),
    );
    if (!contact.hasPhoto) return fallback;
    return FutureBuilder<dynamic>(
      future: contacts.photo(contact),
      builder: (context, snap) {
        final data = snap.data;
        if (data is! Uint8List || data.isEmpty) return fallback;
        return CircleAvatar(radius: radius, backgroundImage: MemoryImage(data));
      },
    );
  }
}

/// The "Contacts" tab: search, favourites, groups, multi-select actions and file tools.
class ContactsScreen extends StatefulWidget {
  final AppStore store;
  const ContactsScreen({super.key, required this.store});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final contacts = ContactStore();
  final search = TextEditingController();
  String query = '';
  String? groupFilter;
  bool favorites = false;
  final Set<int> selected = {};
  /// 0 = الفبا، 1 = الفبا وارونه، 2 = علاقه‌مندی‌ها اول، 3 = تازه‌ترین افزوده‌ها.
  int sort = 0;
  List<PhoneContact> _visible = const [];
  static const _sortNames = ['الفبا (آ تا ی)', 'الفبا (ی تا آ)', 'علاقه‌مندی‌ها اول', 'تازه‌ترین‌ها'];

  List<PhoneContact> _sorted(List<PhoneContact> list) {
    switch (sort) {
      case 1:
        return list.reversed.toList();
      case 2:
        return [...list.where((c) => c.starred), ...list.where((c) => !c.starred)];
      case 3:
        return [...list]..sort((a, b) => b.id.compareTo(a.id));
      default:
        return list;
    }
  }

  Future<void> _mergeAll() async {
    final clusters = contacts.duplicates;
    if (clusters.isEmpty) {
      _notice('مخاطب تکراری پیدا نشد.');
      return;
    }
    final people = Jalali.digits(contacts.duplicateCount);
    final groups = Jalali.digits(clusters.length);
    if (!await confirm(context, 'ادغام همه تکراری‌ها',
        '$people مخاطب در $groups دسته با شماره یا ایمیل مشترک پیدا شدند. قبل از ادغام، از مخاطبین خروجی پشتیبان بگیرید؛ این عمل ممکن است قابل بازگشت نباشد.')) {
      return;
    }
    if (!mounted) return;
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('در حال ادغام…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => LinearProgressIndicator(value: v == 0 ? null : v),
        ),
      ),
    );
    final n = await contacts.mergeAll(progress: (d, t) => progress.value = d / t);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    _notice('${Jalali.digits(n)} دسته تکراری ادغام شد.');
  }

  @override
  void initState() {
    super.initState();
    contacts.load(ask: true);
  }

  @override
  void dispose() {
    contacts.dispose();
    search.dispose();
    super.dispose();
  }

  void _notice(String text) => widget.store.onNotice?.call(text);

  Future<void> _open(PhoneContact c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ContactDetailScreen(store: widget.store, contacts: contacts, contactId: c.id)));
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => ContactEditScreen(contacts: contacts)));
    if (saved != null && saved > 0) _notice('مخاطب ذخیره شد.');
  }

  List<PhoneContact> get _selection => contacts.contacts.where((c) => selected.contains(c.id)).toList();

  Future<void> _bulk(String action) async {
    if (action == 'all') {
      setState(() {
        final all = _visible.every((c) => selected.contains(c.id));
        if (all) {
          selected.clear();
        } else {
          selected.addAll(_visible.map((c) => c.id));
        }
      });
      return;
    }
    final list = _selection;
    if (list.isEmpty) return;
    switch (action) {
      case 'star':
      case 'unstar':
        final n = await contacts.setStar(list, action == 'star');
        _notice(action == 'star' ? '${Jalali.digits(n)} مخاطب به علاقه‌مندی‌ها اضافه شد.' : '${Jalali.digits(n)} مخاطب از علاقه‌مندی‌ها برداشته شد.');
      case 'merge':
        if (list.length < 2) {
          _notice('برای ادغام دست‌کم دو مخاطب انتخاب کنید.');
          return;
        }
        final count = Jalali.digits(list.length);
        if (!await confirm(context, 'ادغام $count مخاطب', 'همه شماره‌ها، ایمیل‌ها و گروه‌ها در یک مخاطب جمع می‌شوند.')) return;
        final ok = await contacts.merge(list);
        _notice(ok ? 'مخاطبان ادغام شدند.' : 'ادغام انجام نشد.');
      case 'ungroup':
        final g = groupFilter == null ? null : contacts.group(groupFilter!);
        if (g == null) return;
        await contacts.removeFromGroup(list, g.id);
        _notice('از گروه «${g.name}» برداشته شد.');
      case 'share':
        final ok = await SmsBridge.shareText(toVcf(list, groupsOf: contacts.groupNamesByKey),
            subject: 'کارت ویزیت', title: 'ارسال مخاطبان');
        if (!ok) _notice('اشتراک‌گذاری در دسترس نیست.');
      case 'group':
        final g = await pickGroup(context, contacts, title: 'افزودن ${Jalali.digits(list.length)} مخاطب به گروه');
        if (g != null) {
          await contacts.addToGroup(list, g.id);
          final name = g.name;
          _notice('به گروه «$name» اضافه شد.');
        }
      case 'sms':
        final numbers = [for (final c in list) if (c.primaryPhone.isNotEmpty) c.primaryPhone];
        if (numbers.isEmpty) {
          _notice('مخاطبان انتخاب‌شده شماره ندارند.');
          return;
        }
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ComposeScreen(store: widget.store, initialRecipients: numbers)));
      case 'export':
        await exportContacts(context, contacts, list);
      case 'delete':
        final count = Jalali.digits(list.length);
        final ok = await confirm(context, 'حذف $count مخاطب', 'مخاطبان از دفترچه تلفن گوشی حذف می‌شوند و قابل بازگشت نیستند.');
        if (ok) {
          final n = await contacts.remove(list);
          final shown = Jalali.digits(n);
          _notice('$shown مخاطب حذف شد.');
        }
    }
    setState(selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: contacts,
      builder: (context, child) {
        final list = _sorted(contacts.search(query, groupId: groupFilter, favorites: favorites));
        _visible = list;
        final selecting = selected.isNotEmpty;
        final allSelected = list.isNotEmpty && list.every((c) => selected.contains(c.id));
        return Scaffold(
          appBar: selecting
              ? AppBar(
                  leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(selected.clear)),
                  title: Text('${Jalali.digits(selected.length)} انتخاب‌شده'),
                  actions: [
                    IconButton(
                      tooltip: allSelected ? 'لغو انتخاب همه' : 'انتخاب همه',
                      icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded),
                      onPressed: () => _bulk('all'),
                    ),
                    IconButton(tooltip: 'پیامک گروهی', icon: const Icon(Icons.sms_outlined), onPressed: () => _bulk('sms')),
                    IconButton(tooltip: 'افزودن به گروه', icon: const Icon(Icons.group_add_outlined), onPressed: () => _bulk('group')),
                    PopupMenuButton<String>(
                      onSelected: _bulk,
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'merge', child: ListTile(dense: true, leading: Icon(Icons.merge_rounded), title: Text('ادغام انتخاب‌شده‌ها'))),
                        const PopupMenuItem(value: 'star', child: ListTile(dense: true, leading: Icon(Icons.star_rounded, color: Color(0xFFE0A526)), title: Text('افزودن به علاقه‌مندی‌ها'))),
                        const PopupMenuItem(value: 'unstar', child: ListTile(dense: true, leading: Icon(Icons.star_border_rounded), title: Text('برداشتن از علاقه‌مندی‌ها'))),
                        if (groupFilter != null)
                          const PopupMenuItem(value: 'ungroup', child: ListTile(dense: true, leading: Icon(Icons.group_remove_outlined), title: Text('برداشتن از این گروه'))),
                        const PopupMenuItem(value: 'share', child: ListTile(dense: true, leading: Icon(Icons.share_rounded), title: Text('ارسال کارت ویزیت'))),
                        const PopupMenuItem(value: 'export', child: ListTile(dense: true, leading: Icon(Icons.download_rounded), title: Text('خروجی از انتخاب‌شده‌ها'))),
                        const PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline_rounded, color: Colors.red), title: Text('حذف از گوشی'))),
                      ],
                    ),
                  ],
                )
              : AppBar(
                  title: const Text('مخاطبین'),
                  actions: [
                    IconButton(
                      tooltip: 'ورود از فایل',
                      icon: const Icon(Icons.upload_file_rounded),
                      onPressed: () => importContacts(context, contacts, onNotice: _notice),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'export':
                            await exportContacts(context, contacts, contacts.contacts);
                          case 'sample':
                            await saveSampleExcel(context, onNotice: _notice);
                          case 'tools':
                            await Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => ContactToolsScreen(store: widget.store, contacts: contacts)));
                          case 'groups':
                            await Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => GroupsManagerScreen(contacts: contacts)));
                          case 'reload':
                            await contacts.load(ask: true);
                          case 'mergeAll':
                            await _mergeAll();
                          case 'select':
                            if (_visible.isNotEmpty) setState(() => selected.addAll(_visible.map((c) => c.id)));
                          case 'sort':
                            final v = await showModalBottomSheet<int>(
                              context: context,
                              showDragHandle: true,
                              builder: (ctx) => SafeArea(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  for (var i = 0; i < _sortNames.length; i++)
                                    ListTile(
                                      leading: Icon(i == sort ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
                                      title: Text(_sortNames[i]),
                                      onTap: () => Navigator.pop(ctx, i),
                                    ),
                                ]),
                              ),
                            );
                            if (v != null) setState(() => sort = v);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'select', child: ListTile(dense: true, leading: Icon(Icons.checklist_rounded), title: Text('انتخاب چندتایی'))),
                        PopupMenuItem(value: 'mergeAll', child: ListTile(dense: true, leading: Icon(Icons.merge_type_rounded), title: Text('ادغام همه تکراری‌ها'))),
                        PopupMenuItem(value: 'sort', child: ListTile(dense: true, leading: Icon(Icons.sort_rounded), title: Text('مرتب‌سازی'))),
                        PopupMenuItem(value: 'export', child: ListTile(dense: true, leading: Icon(Icons.download_rounded), title: Text('خروجی اکسل یا VCF'))),
                        PopupMenuItem(value: 'sample', child: ListTile(dense: true, leading: Icon(Icons.table_view_rounded), title: Text('فایل نمونه اکسل'))),
                        PopupMenuItem(value: 'groups', child: ListTile(dense: true, leading: Icon(Icons.folder_shared_outlined), title: Text('مدیریت گروه‌ها'))),
                        PopupMenuItem(value: 'tools', child: ListTile(dense: true, leading: Icon(Icons.cleaning_services_outlined), title: Text('تکراری‌ها و پاک‌سازی'))),
                        PopupMenuItem(value: 'reload', child: ListTile(dense: true, leading: Icon(Icons.refresh_rounded), title: Text('بارگذاری دوباره'))),
                      ],
                    ),
                  ],
                ),
          floatingActionButton: selecting
              ? null
              : FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('مخاطب جدید')),
          body: !contacts.canRead && !contacts.loading
              ? _PermissionNeeded(onAsk: () => contacts.load(ask: true))
              : RefreshIndicator(
                  onRefresh: contacts.load,
                  child: CustomScrollView(slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                        child: TextField(
                          controller: search,
                          onChanged: (v) => setState(() => query = v),
                          decoration: InputDecoration(
                            hintText: 'جستجوی نام، شماره، ایمیل یا شرکت',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() {
                                      search.clear();
                                      query = '';
                                    })),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _StatsStrip(contacts: contacts, onTools: () {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => ContactToolsScreen(store: widget.store, contacts: contacts)));
                    })),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 52,
                        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: const Text('همه'),
                              selected: !favorites && groupFilter == null,
                              onSelected: (_) => setState(() {
                                favorites = false;
                                groupFilter = null;
                              }),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              avatar: const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE0A526)),
                              label: Text('علاقه‌مندی‌ها ${Jalali.digits(contacts.favoritesCount)}'),
                              selected: favorites,
                              onSelected: (v) => setState(() {
                                favorites = v;
                                groupFilter = null;
                              }),
                            ),
                          ),
                          for (final g in contacts.groups)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: ChoiceChip(
                                avatar: CircleAvatar(radius: 6, backgroundColor: Color(g.color)),
                                label: Text('${g.name} ${Jalali.digits(contacts.countIn(g.id))}'),
                                selected: groupFilter == g.id,
                                onSelected: (v) => setState(() {
                                  groupFilter = v ? g.id : null;
                                  favorites = false;
                                }),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    if (contacts.loading && contacts.contacts.isEmpty)
                      const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))),
                    if (!contacts.loading && list.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(children: [
                            Icon(Icons.person_search_rounded, size: 56, color: scheme.outline),
                            const SizedBox(height: 10),
                            Text(query.isEmpty ? 'مخاطبی در این بخش نیست' : 'نتیجه‌ای پیدا نشد',
                                style: Theme.of(context).textTheme.titleMedium),
                          ]),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          final header = i == 0 || list[i - 1].initial != c.initial;
                          final groups = contacts.groupsOf(c);
                          final isSelected = selected.contains(c.id);
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (header && query.isEmpty && sort < 2)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                                child: Text(c.initial, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900)),
                              ),
                            ListTile(
                              selected: isSelected,
                              selectedTileColor: scheme.primaryContainer.withValues(alpha: .4),
                              leading: isSelected
                                  ? CircleAvatar(radius: 22, backgroundColor: scheme.primary, child: Icon(Icons.check_rounded, color: scheme.onPrimary))
                                  : ContactAvatar(contacts: contacts, contact: c),
                              title: Row(children: [
                                Flexible(child: Text(c.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700))),
                                if (c.starred) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(Icons.star_rounded, size: 16, color: Color(0xFFE0A526))),
                              ]),
                              subtitle: Row(children: [
                                for (final g in groups.take(3))
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(end: 4),
                                    child: CircleAvatar(radius: 4, backgroundColor: Color(g.color)),
                                  ),
                                Expanded(
                                  child: Text(
                                    c.primaryPhone.isNotEmpty ? Jalali.digits(c.primaryPhone) : (c.emails.isNotEmpty ? c.emails.first.value : c.org),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ]),
                              onTap: () => selecting
                                  ? setState(() => isSelected ? selected.remove(c.id) : selected.add(c.id))
                                  : _open(c),
                              onLongPress: () => setState(() => selected.add(c.id)),
                            ),
                          ]);
                        },
                      ),
                    ),
                  ]),
                ),
        );
      },
    );
  }
}

class _StatsStrip extends StatelessWidget {
  final ContactStore contacts;
  final VoidCallback onTools;
  const _StatsStrip({required this.contacts, required this.onTools});

  @override
  Widget build(BuildContext context) {
    final dup = contacts.duplicates.length;
    final bad = contacts.incomplete.length + contacts.untidy.length;
    Widget box(String label, String value, IconData icon, List<Color> colors, {VoidCallback? onTap}) => Expanded(
          child: Material(
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topRight, end: Alignment.bottomLeft)),
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(height: 3),
                    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Row(children: [
        box('مخاطب', Jalali.digits(contacts.contacts.length), Icons.contacts_rounded, const [Color(0xFF087F81), Color(0xFF12444C)]),
        const SizedBox(width: 8),
        box('علاقه‌مندی', Jalali.digits(contacts.favoritesCount), Icons.star_rounded, const [Color(0xFFE0A526), Color(0xFFA17A37)]),
        const SizedBox(width: 8),
        box('تکراری', Jalali.digits(dup), Icons.copy_all_rounded, const [Color(0xFF75539A), Color(0xFF3F3A88)], onTap: onTools),
        const SizedBox(width: 8),
        box('نیاز به اصلاح', Jalali.digits(bad), Icons.healing_rounded, const [Color(0xFFC0583B), Color(0xFF9F5369)], onTap: onTools),
      ]),
    );
  }
}

class _PermissionNeeded extends StatelessWidget {
  final VoidCallback onAsk;
  const _PermissionNeeded({required this.onAsk});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.contacts_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            const Text('برای مدیریت مخاطبین، اجازه دسترسی به دفترچه تلفن لازم است.', textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('اطلاعات فقط روی همین گوشی پردازش می‌شود.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onAsk, icon: const Icon(Icons.lock_open_rounded), label: const Text('اجازه دسترسی')),
          ]),
        ),
      );
}
