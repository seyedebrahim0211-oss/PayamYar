import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../sms_bridge.dart';
import 'compose_screen.dart';
import 'home_screen.dart';
import 'widgets.dart';

class ConversationScreen extends StatefulWidget {
  final AppStore store;
  final String address;
  const ConversationScreen({super.key, required this.store, required this.address});
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final input = TextEditingController();
  bool sending = false;
  AppStore get store => widget.store;

  /// Alphanumeric senders (banks, services) cannot receive replies.
  bool get canReply => RegExp(r'\d{3,}').hasMatch(SmsBridge.normalizeNumber(widget.address));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = store.conversationFor(widget.address);
      if (c != null) store.markRead(c);
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    final pending = await store.send(widget.address, text);
    if (!mounted) return;
    setState(() => sending = false);
    if (pending != null || !store.android) input.clear();
    if (pending != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: const Text('پیام تا ۵ ثانیه دیگر ارسال می‌شود'),
          action: SnackBarAction(label: 'لغو', onPressed: () async {
            if (await store.undo(pending)) input.text = pending.body;
          })));
    }
  }

  void _messageActions(MessageRecord m) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('کپی متن'), onTap: () {
          Clipboard.setData(ClipboardData(text: m.body));
          Navigator.pop(ctx);
          store.onNotice?.call('متن کپی شد.');
        }),
        ListTile(leading: const Icon(Icons.forward_rounded), title: const Text('بازارسال'), onTap: () {
          Navigator.pop(ctx);
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComposeScreen(store: store, initialBody: m.body)));
        }),
        if (m.id != null)
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
            title: Text('حذف پیام', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
                title: const Text('حذف پیام؟'),
                content: const Text('این پیام برای همیشه از گوشی حذف می‌شود.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('انصراف')),
                  TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('حذف')),
                ]));
              if (ok == true) await store.deleteMessages([m.id!]);
            }),
      ])),
    );
  }

  Future<void> _menu(String value) async {
    final c = store.conversationFor(widget.address);
    switch (value) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: widget.address));
        store.onNotice?.call('شماره کپی شد.');
      case 'pin':
        store.togglePin(widget.address);
      case 'archive':
        store.toggleArchive(widget.address);
        if (mounted) Navigator.pop(context);
      case 'block':
        await store.block(widget.address);
      case 'delete':
        if (c == null) return;
        await confirmDeleteConversation(context, store, c);
        if (mounted && store.conversationFor(widget.address) == null) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.conversationFor(widget.address);
        final messages = c?.messages ?? const <MessageRecord>[];
        final name = store.displayName(widget.address);
        final key = store.key(widget.address);
        final pending = store.pendingSends.where((p) => store.key(p.to) == key).toList();
        final items = <Widget>[];
        for (final p in pending.reversed) {
          items.add(_Bubble(text: p.body, outgoing: true, time: 'در صف ارسال',
            trailing: TextButton(onPressed: () async {
              if (await store.undo(p)) input.text = p.body;
            }, child: const Text('لغو'))));
        }
        for (var i = 0; i < messages.length; i++) {
          final m = messages[i];
          items.add(_bubbleFor(m));
          final next = i + 1 < messages.length ? messages[i + 1] : null;
          if (next == null || !_sameDay(next.date, m.date)) items.add(_DayHeader(Jalali.dayHeader(m.date)));
        }
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(children: [
              SenderAvatar(name: name, address: widget.address, radius: 19,
                category: messages.isEmpty ? MessageCategory.personal : MessageLogic.category(messages.first)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
                if (name != widget.address)
                  Text(widget.address, textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant)),
              ])),
            ]),
            actions: [
              PopupMenuButton<String>(
                onSelected: _menu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy', child: Text('کپی شماره')),
                  PopupMenuItem(value: 'pin', child: Text(store.isPinned(widget.address) ? 'برداشتن سنجاق' : 'سنجاق کردن')),
                  PopupMenuItem(value: 'archive', child: Text(store.isArchived(widget.address) ? 'خارج کردن از بایگانی' : 'بایگانی')),
                  if (SmsBridge.supported) const PopupMenuItem(value: 'block', child: Text('مسدود کردن')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف گفتگو')),
                ]),
            ],
          ),
          body: Column(children: [
            Expanded(child: items.isEmpty
                ? const EmptyState(icon: Icons.chat_outlined, title: 'هنوز پیامی نیست', subtitle: 'اولین پیام را بنویسید.')
                : ListView(reverse: true, padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), children: items)),
            if (canReply) _inputBar(scheme) else Padding(
              padding: const EdgeInsets.all(14),
              child: Text('امکان پاسخ به این فرستنده وجود ندارد.', style: TextStyle(color: scheme.onSurfaceVariant))),
          ]),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _bubbleFor(MessageRecord m) {
    String? status;
    if (m.outgoing) {
      status = m.type == 5
          ? 'ارسال نشد'
          : m.type == 4 || m.type == 6
              ? 'در حال ارسال'
              : m.type == 3
                  ? 'پیش‌نویس'
                  : m.delivery == 0
                      ? 'تحویل شد ✓✓'
                      : m.delivery >= 64
                          ? 'تحویل ناموفق'
                          : 'ارسال شد ✓';
    }
    final code = m.outgoing ? null : MessageLogic.otp(m.body);
    return _Bubble(
      text: m.body,
      outgoing: m.outgoing,
      failed: m.type == 5,
      warning: !m.outgoing && MessageLogic.suspicious(m.body),
      time: '${Jalali.time(m.date)}${status == null ? '' : ' • $status'}',
      onLongPress: () => _messageActions(m),
      trailing: code == null ? null : ActionChip(
        avatar: const Icon(Icons.copy_rounded, size: 16),
        label: Text('کپی کد ${Jalali.digits(code)}'),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: code));
          store.onNotice?.call('کد $code کپی شد.');
        }),
    );
  }

  Widget _inputBar(ColorScheme scheme) {
    final dualSim = store.sims.length > 2;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          PopupMenuButton<String>(
            tooltip: 'پیام‌های آماده',
            icon: Icon(Icons.bolt_rounded, color: scheme.primary),
            onSelected: (t) => input.text = t,
            itemBuilder: (_) => [for (final t in store.templates) PopupMenuItem(value: t, child: Text(t))],
          ),
          if (dualSim)
            PopupMenuButton<int>(
              tooltip: 'انتخاب سیم‌کارت',
              icon: Icon(Icons.sim_card_outlined, color: scheme.primary),
              onSelected: (v) => setState(() => store.selectedSim = v),
              itemBuilder: (_) => [
                for (final s in store.sims)
                  CheckedPopupMenuItem(value: s['id'] as int, checked: store.selectedSim == s['id'], child: Text(s['label'].toString())),
              ],
            ),
          Expanded(child: TextField(
            controller: input,
            minLines: 1,
            maxLines: 5,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(hintText: 'پیام بنویسید…', counterText: '',
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          )),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'ارسال',
            onPressed: sending ? null : _send,
            icon: const Icon(Icons.send_rounded, textDirection: TextDirection.ltr),
          ),
        ]),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader(this.label);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(child: Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ));
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool outgoing;
  final bool failed;
  final bool warning;
  final String time;
  final Widget? trailing;
  final VoidCallback? onLongPress;
  const _Bubble({required this.text, required this.outgoing, required this.time,
    this.failed = false, this.warning = false, this.trailing, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = failed ? scheme.errorContainer : outgoing ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = failed ? scheme.onErrorContainer : outgoing ? scheme.onPrimary : scheme.onSurface;
    const r = Radius.circular(20);
    return Align(
      alignment: outgoing ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadiusDirectional.only(
                topStart: r, topEnd: r,
                bottomStart: outgoing ? r : const Radius.circular(6),
                bottomEnd: outgoing ? const Radius.circular(6) : r,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (warning)
                const Padding(padding: EdgeInsets.only(bottom: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('احتمال کلاهبرداری؛ روی لینک نزنید', style: TextStyle(fontSize: 12, color: Colors.orange)),
                ])),
              Text(text, style: TextStyle(color: fg, fontSize: 15, height: 1.6)),
              if (trailing != null) Padding(padding: const EdgeInsets.only(top: 6), child: trailing),
              const SizedBox(height: 4),
              Text(time, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}
