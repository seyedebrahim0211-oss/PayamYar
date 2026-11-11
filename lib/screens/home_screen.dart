import 'package:flutter/material.dart';
import '../app_store.dart';
import '../brand_mark.dart';
import '../conversation_logic.dart';
import '../jalali.dart';
import '../app_settings.dart';
import '../message_logic.dart';
import '../sms_bridge.dart';
import 'compose_screen.dart';
import 'conversation_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  const HomeShell({super.key, required this.store, required this.settings});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.onComposeIntent = _takeIntent;
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeIntent());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.onComposeIntent = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.refresh();
      _takeIntent();
    }
  }

  /// sms:/smsto: links from other apps open the composer prefilled; nothing is sent automatically.
  Future<void> _takeIntent() async {
    if (!SmsBridge.supported) return;
    final value = await SmsBridge.composeIntent();
    if (value == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComposeScreen(
      store: widget.store, initialTo: value['to']?.toString() ?? '', initialBody: value['body']?.toString() ?? '')));
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.store.conversations.where((c) => widget.store.unreadCount(c) > 0).length;
    final pages = [
      ConversationsPage(store: widget.store, settings: widget.settings),
      ReportsScreen(store: widget.store, settings: widget.settings),
      SettingsScreen(store: widget.store, settings: widget.settings),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ComposeScreen(store: widget.store))),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('پیام جدید'))
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text(Jalali.digits(unread)), child: const Icon(Icons.chat_bubble_outline_rounded)),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: 'گفتگوها'),
          const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'گزارش‌ها'),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'تنظیمات'),
        ],
      ),
    );
  }
}

class ConversationsPage extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  final bool archive;
  const ConversationsPage({super.key, required this.store, required this.settings, this.archive = false});
  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  bool searching = false;
  String query = '';
  bool unreadOnly = false;
  MessageCategory? category;
  final search = TextEditingController();

  AppStore get store => widget.store;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<Conversation> _filtered() {
    final q = query.trim().toLowerCase();
    return store.visible(archive: widget.archive).where((c) {
      if (unreadOnly && store.unreadCount(c) == 0) return false;
      if (category != null && MessageLogic.category(c.latest) != category) return false;
      if (q.isEmpty) return true;
      if (store.displayName(c.address).toLowerCase().contains(q) || c.address.toLowerCase().contains(q)) return true;
      return c.messages.any((m) => m.body.toLowerCase().contains(q));
    }).toList();
  }

  void _actions(Conversation c) {
    final unread = store.unreadCount(c) > 0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(store.displayName(c.address), style: const TextStyle(fontWeight: FontWeight.w800))),
        ListTile(
          leading: Icon(store.isPinned(c.address) ? Icons.push_pin_outlined : Icons.push_pin_rounded),
          title: Text(store.isPinned(c.address) ? 'برداشتن سنجاق' : 'سنجاق کردن بالای فهرست'),
          onTap: () { Navigator.pop(ctx); store.togglePin(c.address); }),
        if (unread)
          ListTile(leading: const Icon(Icons.mark_chat_read_outlined), title: const Text('علامت‌گذاری به‌عنوان خوانده‌شده'),
            onTap: () { Navigator.pop(ctx); store.markRead(c); }),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(store.isArchived(c.address) ? 'خارج کردن از بایگانی' : 'بایگانی'),
          onTap: () { Navigator.pop(ctx); store.toggleArchive(c.address); }),
        if (SmsBridge.supported)
          ListTile(leading: const Icon(Icons.block_rounded), title: const Text('مسدود کردن فرستنده'),
            onTap: () { Navigator.pop(ctx); store.block(c.address); }),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
          title: Text('حذف گفتگو', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          onTap: () async {
            Navigator.pop(ctx);
            await confirmDeleteConversation(context, store, c);
          }),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([store, widget.settings]),
      builder: (context, _) {
        final list = _filtered();
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: searching
                ? TextField(
                    controller: search,
                    autofocus: true,
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(hintText: 'جستجو در نام‌ها و پیام‌ها', isDense: true,
                      prefixIcon: Icon(Icons.search_rounded)))
                : widget.archive
                    ? const Text('بایگانی')
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
                          child: const BrandMark()),
                        const SizedBox(width: 10),
                        const Text('پیامیار'),
                      ]),
            actions: [
              IconButton(
                tooltip: searching ? 'بستن جستجو' : 'جستجو',
                icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  searching = !searching;
                  if (!searching) { search.clear(); query = ''; }
                })),
              if (!widget.archive)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'archive') {
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                        ConversationsPage(store: store, settings: widget.settings, archive: true)));
                    } else if (v == 'read') {
                      store.markAllRead();
                    } else if (v == 'blocked') {
                      SmsBridge.manageBlocked();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                    const PopupMenuItem(value: 'read', child: Text('خواندن همه')),
                    if (SmsBridge.supported) const PopupMenuItem(value: 'blocked', child: Text('شماره‌های مسدود')),
                  ]),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: store.android ? store.loadAll : () async {},
            child: CustomScrollView(slivers: [
              if (store.android && !store.isDefault && !widget.archive)
                SliverToBoxAdapter(child: _DefaultBanner(store: store)),
              if (store.loadingAll)
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(children: [
                    const LinearProgressIndicator(borderRadius: BorderRadius.all(Radius.circular(4))),
                    const SizedBox(height: 6),
                    Text('در حال آوردن پیام‌های گوشی… ${Jalali.digits(store.messages.length)} پیام',
                      style: Theme.of(context).textTheme.bodySmall),
                  ]))),
              if (!widget.archive)
                SliverToBoxAdapter(child: SizedBox(height: 52, child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _chip('همه', !unreadOnly && category == null, () => setState(() { unreadOnly = false; category = null; })),
                    _chip('خوانده‌نشده', unreadOnly, () => setState(() { unreadOnly = !unreadOnly; })),
                    for (final c in MessageCategory.values)
                      _chip(categoryName(c), category == c, () => setState(() => category = category == c ? null : c)),
                  ]))),
              if (store.error != null)
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16),
                  child: Text(store.error!, style: TextStyle(color: scheme.error)))),
              if (list.isEmpty && !store.loadingAll)
                SliverToBoxAdapter(child: EmptyState(
                  icon: query.isNotEmpty ? Icons.search_off_rounded : Icons.forum_outlined,
                  title: query.isNotEmpty ? 'نتیجه‌ای پیدا نشد' : widget.archive ? 'بایگانی خالی است' : 'پیامی وجود ندارد',
                  subtitle: widget.archive ? 'گفتگوها را با نگه داشتن انگشت روی آن‌ها بایگانی کنید.' : null)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 96),
                sliver: SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => ConversationTile(
                    store: store,
                    conversation: list[i],
                    hidePreview: widget.settings.hidePreview,
                    onLongPress: () => _actions(list[i]),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      shape: const StadiumBorder(),
    ),
  );
}

class _DefaultBanner extends StatelessWidget {
  final AppStore store;
  const _DefaultBanner({required this.store});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Card(
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Icon(Icons.star_rounded, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(child: Text('پیامیار را پیام‌رسان پیش‌فرض کنید تا پیام‌های جدید را دریافت و مدیریت کند.',
              style: TextStyle(color: scheme.onPrimaryContainer))),
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: store.requestDefault,
              child: const Text('فعال‌سازی')),
          ]),
        ),
      ),
    );
  }
}

class ConversationTile extends StatelessWidget {
  final AppStore store;
  final Conversation conversation;
  final bool hidePreview;
  final VoidCallback onLongPress;
  const ConversationTile({super.key, required this.store, required this.conversation, required this.hidePreview, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = conversation.latest;
    final unread = store.unreadCount(conversation);
    final name = store.displayName(conversation.address);
    final bold = unread > 0;
    final preview = hidePreview ? 'متن پیام مخفی است' : '${m.outgoing ? 'شما: ' : ''}${m.body.replaceAll('\n', ' ')}';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(store: store, address: conversation.address))),
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(children: [
          SenderAvatar(name: name, address: conversation.address, category: MessageLogic.category(m)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                textDirection: name == conversation.address && RegExp(r'^[\d+]').hasMatch(name) ? TextDirection.ltr : null,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.w800 : FontWeight.w600))),
              if (store.isPinned(conversation.address))
                Padding(padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Icon(Icons.push_pin_rounded, size: 16, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Text(Jalali.short(m.date), style: TextStyle(fontSize: 12,
                color: bold ? scheme.primary : scheme.onSurfaceVariant, fontWeight: bold ? FontWeight.w700 : null)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              if (MessageLogic.suspicious(m.body))
                const Padding(padding: EdgeInsetsDirectional.only(end: 4),
                  child: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange)),
              Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: bold ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: bold ? FontWeight.w600 : null))),
              if (unread > 0)
                Container(
                  margin: const EdgeInsetsDirectional.only(start: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
                  child: Text(Jalali.digits(unread), style: TextStyle(color: scheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w700))),
            ]),
          ])),
        ]),
      ),
    );
  }
}

Future<void> confirmDeleteConversation(BuildContext context, AppStore store, Conversation c) async {
  final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
    title: const Text('حذف گفتگو؟'),
    content: Text('همه ${Jalali.digits(c.count)} پیام گفتگو با ${store.displayName(c.address)} برای همیشه از گوشی حذف می‌شود.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('انصراف')),
      TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('حذف')),
    ]));
  if (ok != true) return;
  await store.deleteMessages(c.messages.where((m) => m.id != null).map((m) => m.id!).toList());
}
