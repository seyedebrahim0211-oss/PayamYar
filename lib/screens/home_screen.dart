import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../brand_mark.dart';
import '../conversation_logic.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../sms_bridge.dart';
import '../update_service.dart' show formatBytes;
import '../contacts/contacts_screen.dart';
import 'compose_screen.dart';
import 'conversation_screen.dart';
import 'reports_screen.dart';
import 'groups_screen.dart';
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
  DateTime? _lastUpdateCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.onComposeIntent = _takeIntent;
    widget.store.onOpenConversation = _openConversation;
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeIntent());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.onComposeIntent = null;
    widget.store.onOpenConversation = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.checkPermissions();
      widget.store.refresh();
      unawaited(widget.store.resumePendingUpdate());
      final now = DateTime.now();
      if (_lastUpdateCheck == null ||
          now.difference(_lastUpdateCheck!) > const Duration(minutes: 30)) {
        _lastUpdateCheck = now;
        unawaited(widget.store.checkForUpdate());
      }
      _takeIntent();
    }
  }

  /// Opens a chat from the in-app glass banner.
  void _openConversation(String address) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(store: widget.store, address: address)));
  }

  /// Opens the conversation of a tapped notification, or the composer for sms:/smsto: links.
  /// Nothing is ever sent automatically.
  Future<void> _takeIntent() async {
    if (!SmsBridge.supported) return;
    final value = await SmsBridge.composeIntent();
    if (value == null || !mounted) return;
    final open = value['open']?.toString();
    final to = Uri.decodeComponent(value['to']?.toString() ?? '').trim();
    final body = value['body']?.toString() ?? '';
    // "Message" from the phone's Contacts app (smsto:NUMBER) goes straight into that
    // person's chat, keeping its history; several recipients still open the composer.
    final single = to.isNotEmpty && !to.contains(RegExp('[,;]')) &&
        RegExp(r'^\+?\d{3,15}$').hasMatch(SmsBridge.normalizeNumber(to).replaceAll(RegExp(r'[\s()-]'), ''));
    final address = open ?? (single ? (widget.store.conversationFor(to)?.address ?? to) : null);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => address != null
        ? ConversationScreen(store: widget.store, address: address, initialText: open != null ? '' : body)
        : ComposeScreen(store: widget.store, initialTo: to, initialBody: body)));
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.store.unreadConversations;
    return Scaffold(
      extendBody: true, // Let content show through the frosted navigation surface.
      // The inbox stays alive (keeps scroll and search); the other tabs are built only while open.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // A fast, intentional horizontal swipe changes the section. Short
        // gestures and vertical list scrolling keep their native behavior.
        onHorizontalDragEnd: widget.settings.swipeTabs ? (details) {
          final speed = details.primaryVelocity ?? 0;
          if (speed.abs() < 500) return;
          final direction = speed < 0 ? 1 : -1;
          final next = (tab + direction).clamp(0, 4);
          if (next != tab && mounted) setState(() => tab = next);
        } : null,
        child: Stack(children: [
          Offstage(
            offstage: tab != 0,
            child: TickerMode(enabled: tab == 0, child: ConversationsPage(store: widget.store, settings: widget.settings))),
          if (tab == 1) ContactsScreen(store: widget.store),
          if (tab == 2) GroupsScreen(store: widget.store),
          if (tab == 3) ReportsScreen(store: widget.store, settings: widget.settings),
          if (tab == 4) SettingsScreen(store: widget.store, settings: widget.settings),
        ]),
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ComposeScreen(store: widget.store))),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('پیام جدید'))
          : null,
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: widget.settings.reduceEffects ? 0 : 14,
            sigmaY: widget.settings.reduceEffects ? 0 : 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: .78),
              border: Border(top: BorderSide(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .18))),
            ),
            child: NavigationBar(
        elevation: 0,
        height: 73,
        backgroundColor: Colors.transparent,
        indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text(Jalali.digits(unread)), child: const Icon(Icons.chat_bubble_outline_rounded)),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: 'گفتگوها'),
          const NavigationDestination(icon: Icon(Icons.contacts_outlined), selectedIcon: Icon(Icons.contacts_rounded), label: 'مخاطبین'),
          const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'گروه‌ها'),
          const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'گزارش‌ها'),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'تنظیمات'),
        ],
            ),
          ),
        ),
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
    final all = store.visible(archive: widget.archive);
    if (!unreadOnly && category == null && q.isEmpty) return all;
    return all.where((c) {
      if (unreadOnly && store.unreadCount(c) == 0) return false;
      if (category != null && store.categoryOf(c) != category) return false;
      if (q.isEmpty) return true;
      if (store.displayName(c.address).toLowerCase().contains(q) || c.address.toLowerCase().contains(q)) return true;
      return c.messages.any((m) => m.body.toLowerCase().contains(q));
    }).toList();
  }

  void _actions(Conversation c) {
    final unread = store.unreadCount(c) > 0;
    final isPinned = store.isPinned(c.address);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(store.displayName(c.address), style: const TextStyle(fontWeight: FontWeight.w800))),
        ListTile(
          leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
          title: Text(isPinned ? 'برداشتن سنجاق' : 'سنجاق کردن بالای فهرست'),
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

  /// Left/right gestures cycle inbox views; archiving is an intentional
  /// long-press action and cannot be triggered by an accidental swipe.
  void _cycleInbox(double velocity) {
    if (widget.archive || velocity.abs() < 460) return;
    final current = unreadOnly ? 1 : category == null
        ? 0 : MessageCategory.values.indexOf(category!) + 2;
    final next = (current + (velocity < 0 ? 1 : -1))
        .clamp(0, MessageCategory.values.length + 1);
    if (next == current) return;
    setState(() {
      unreadOnly = next == 1;
      category = next >= 2 ? MessageCategory.values[next - 2] : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([store, widget.settings]),
      builder: (context, _) {
        final list = _filtered();
        final unread = store.unreadConversations;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            toolbarHeight: 64,
            title: widget.archive
                ? const Text('بایگانی')
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const BrandTile(size: 42),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      const Text('پیامیار', style: TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w900, fontSize: 21)),
                      Text(unread > 0 ? '${Jalali.digits(unread)} گفتگوی خوانده‌نشده' : 'همه پیام‌ها خوانده شده',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400,
                          color: unread > 0 ? scheme.primary : scheme.onSurfaceVariant)),
                    ]),
                  ]),
            actions: [
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
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              if (widget.settings.swipeTabs) _cycleInbox(details.primaryVelocity ?? 0);
            },
            child: RefreshIndicator(
            onRefresh: store.android ? store.loadAll : () async {},
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                child: TextField(
                  controller: search,
                  onChanged: (v) => setState(() => query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'جستجو در نام‌ها و پیام‌ها',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty ? null : IconButton(
                      tooltip: 'پاک کردن جستجو',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() { search.clear(); query = ''; })),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none)),
                ))),
              if (store.update != null && !store.updateDismissed && !widget.archive)
                SliverToBoxAdapter(child: UpdateBanner(store: store)),
              if (store.android && !store.isDefault && !widget.archive)
                SliverToBoxAdapter(child: _ActionBanner(
                  icon: Icons.star_rounded,
                  text: 'پیامیار را پیام‌رسان پیش‌فرض کنید تا پیام‌های جدید را دریافت و مدیریت کند.',
                  action: 'فعال‌سازی',
                  onTap: store.requestDefault))
              else if (store.android && !store.access.complete && !widget.archive)
                SliverToBoxAdapter(child: _ActionBanner(
                  icon: Icons.bolt_rounded,
                  text: 'برای دریافت مطمئن پیام‌ها و اعلان‌ها، دسترسی‌های ویژه را کامل کنید.',
                  action: 'تنظیم',
                  onTap: () => showSpecialAccessSheet(context, store))),
              // The whole inbox loads silently in the background; only a first-run empty
              // inbox shows a small spinner instead of the "no messages" state.
              if (store.loadingAll && list.isEmpty && query.isEmpty)
                const SliverToBoxAdapter(child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()))),
              if (!widget.archive)
                SliverToBoxAdapter(child: SizedBox(height: 50, child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                  subtitle: widget.archive ? 'گفتگوها را با کشیدن به کنار بایگانی کنید.' : null)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                sliver: SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final c = list[i];
                    return ConversationTile(
                      key: ValueKey('conv-${store.key(c.address)}'),
                      store: store,
                      conversation: c,
                      hidePreview: widget.settings.hidePreview,
                      onLongPress: () => _actions(c),
                    );
                  },
                ),
              ),
            ]),
            ),
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

/// "New version available" card; downloads, verifies and opens Android's installer inside the app.
class UpdateBanner extends StatelessWidget {
  final AppStore store;
  const UpdateBanner({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final info = store.update!;
    final progress = store.updateProgress;
    final error = store.updateError;
    final downloading = progress != null;
    const ink = Colors.white;
    final meta = [
      'نسخه ${Jalali.digits(info.version)}',
      if (info.sizeLabel.isNotEmpty) info.sizeLabel,
      'از هنر مردمی',
    ].join('  •  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Semantics(
        container: true,
        label: 'به‌روزرسانی پیامیار',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
              colors: [Color(0xFF0B8C8A), Color(0xFF075A61), Color(0xFF0B3C44)]),
            boxShadow: const [BoxShadow(color: Color(0x33075A61), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Stack(children: [
            const Positioned(left: -18, top: -22, child: Opacity(opacity: .10,
              child: Icon(Icons.auto_awesome_rounded, size: 120, color: Color(0xFFFFD27A)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(14)),
                    child: Icon(error != null ? Icons.wifi_off_rounded : Icons.rocket_launch_rounded,
                      color: const Color(0xFFFFD27A)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(error != null ? 'دریافت به‌روزرسانی کامل نشد' : 'پیامیار تازه‌تر آماده است',
                      style: const TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 15.5)),
                    Text(meta, style: const TextStyle(color: Color(0xFFCFE9E4), fontSize: 12)),
                  ])),
                  if (!downloading)
                    IconButton(tooltip: 'بعداً', onPressed: store.dismissUpdate,
                      icon: const Icon(Icons.close_rounded, color: Color(0xFFCFE9E4))),
                ]),
                if (error != null)
                  Padding(padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(12)),
                      child: Text(error, style: const TextStyle(color: Color(0xFFFFE2D6), fontSize: 12.5, height: 1.7))))
                else if (info.notes.isNotEmpty && !downloading)
                  Padding(padding: const EdgeInsets.only(top: 10),
                    child: Text(info.notes, maxLines: 4, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFE6F4F1), fontSize: 13, height: 1.75))),
                const SizedBox(height: 12),
                if (progress != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: progress == 0 ? null : progress,
                      color: const Color(0xFFFFD27A),
                      backgroundColor: const Color(0x33FFFFFF)),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.verified_user_rounded, size: 15, color: Color(0xFFCFE9E4)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      progress >= 1 ? 'در حال بررسی امضا و صحت فایل…' : 'دریافت امن… ${Jalali.digits((progress * 100).round())}٪',
                      style: const TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w600))),
                    if (store.updateTotal > 0)
                      Text('${formatBytes(store.updateReceived)} از ${formatBytes(store.updateTotal)}',
                        style: const TextStyle(color: Color(0xFFCFE9E4), fontSize: 11.5)),
                  ]),
                ] else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: const Color(0xFFFFD27A),
                      foregroundColor: const Color(0xFF3A2A05)),
                    onPressed: store.installUpdate,
                    icon: Icon(error != null ? Icons.refresh_rounded : Icons.download_for_offline_rounded, size: 20),
                    label: Text(error != null ? 'تلاش دوباره' : 'دریافت و نصب به‌روزرسانی')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ActionBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;
  const _ActionBanner({required this.icon, required this.text, required this.action, required this.onTap});
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
            Icon(icon, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: scheme.onPrimaryContainer))),
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: onTap,
              child: Text(action)),
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
    final info = store.infoFor(conversation.address);
    final unread = info?.unread ?? 0;
    final name = store.displayName(conversation.address);
    final pinned = store.isPinned(conversation.address);
    final bold = unread > 0;
    final preview = hidePreview ? 'متن پیام مخفی است' : '${m.outgoing ? 'شما: ' : ''}${m.body.replaceAll('\n', ' ')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: pinned ? scheme.primaryContainer.withValues(alpha: .38) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ConversationScreen(store: store, address: conversation.address))),
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              SenderAvatar(name: name, address: conversation.address, category: info?.category ?? MessageCategory.personal),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    textDirection: name == conversation.address && RegExp(r'^[\d+]').hasMatch(name) ? TextDirection.ltr : null,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.w800 : FontWeight.w600))),
                  if (pinned)
                    const Padding(padding: EdgeInsetsDirectional.only(start: 4),
                      child: Icon(Icons.push_pin_rounded, size: 16, color: Color(0xFFB8862E))),
                  const SizedBox(width: 6),
                  Text(Jalali.short(m.date), style: TextStyle(fontSize: 12,
                    color: bold ? scheme.primary : scheme.onSurfaceVariant, fontWeight: bold ? FontWeight.w700 : null)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  if (info?.suspicious ?? false)
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
        ),
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

/// Android "special access" switches that keep PayamYar working reliably in the background.
Future<void> showSpecialAccessSheet(BuildContext context, AppStore store) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: store,
      builder: (ctx, _) {
        final a = store.access;
        Widget row(bool ok, IconData icon, String title, String body, Future<void> Function() open) => ListTile(
          leading: Icon(icon, color: Theme.of(ctx).colorScheme.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(body),
          trailing: ok
              ? const Icon(Icons.check_circle_rounded, color: Colors.green)
              : FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                  onPressed: open,
                  child: const Text('فعال‌سازی')),
        );
        return SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('دسترسی‌های ویژه',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            row(a.notifications, Icons.notifications_active_rounded, 'اعلان‌ها',
              'نمایش پیام جدید با پاسخ سریع و کپی کد', SmsBridge.openNotificationSettings),
            row(a.battery, Icons.battery_charging_full_rounded, 'اجرا بدون محدودیت باتری',
              'تا اندروید دریافت پیام در پس‌زمینه را متوقف نکند', SmsBridge.requestBatteryExemption),
            row(a.exactAlarm, Icons.alarm_on_rounded, 'زمان‌بندی دقیق',
              'برای ارسال سر وقت و مهلت لغو ۵ ثانیه‌ای', SmsBridge.requestExactAlarm),
            const SizedBox(height: 6),
            Text('پس از بازگشت از تنظیمات گوشی، وضعیت خودکار به‌روز می‌شود.',
              style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ));
      },
    ),
  );
}
