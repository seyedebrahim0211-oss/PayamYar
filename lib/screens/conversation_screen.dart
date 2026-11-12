import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../sms_bridge.dart';
import '../smart_assistant.dart';
import 'compose_screen.dart';
import 'compose_tools.dart';
import 'send_control.dart';
import 'home_screen.dart';
import 'widgets.dart';

class ConversationScreen extends StatefulWidget {
  final AppStore store;
  final String address;
  const ConversationScreen({super.key, required this.store, required this.address});
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

/// One row of the chat list: a queued send, a message, or a day separator.
class _Entry {
  final MessageRecord? message;
  final PendingSend? pending;
  final String? header;
  const _Entry({this.message, this.pending, this.header});
}

class _ConversationScreenState extends State<ConversationScreen> {
  final input = TextEditingController();
  bool sending = false;
  AppStore get store => widget.store;

  /// Alphanumeric senders (banks, services) cannot receive replies.
  bool get canReply => RegExp(r'\d{3,}').hasMatch(SmsBridge.normalizeNumber(widget.address));
  bool get isPhone => RegExp(r'^\+?\d{7,15}$').hasMatch(SmsBridge.normalizeNumber(widget.address).replaceAll(RegExp(r'[\s()-]'), ''));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
    store.addListener(_onStoreChanged);
  }

  /// A message that arrives while this conversation is open is marked read right away.
  void _onStoreChanged() {
    if ((store.infoFor(widget.address)?.unread ?? 0) > 0) Future.microtask(_markRead);
  }

  void _markRead() {
    if (!mounted) return;
    final c = store.conversationFor(widget.address);
    if (c != null) store.markRead(c);
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    input.dispose();
    super.dispose();
  }

  Future<void> _send({DateTime? scheduledAt}) async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    final pending = await store.send(widget.address, text, scheduledAt: scheduledAt);
    if (!mounted) return;
    setState(() => sending = false);
    if (pending != null || !store.android) input.clear();
    if (pending != null && scheduledAt != null) {
      store.onNotice?.call('ارسال برای ${Jalali.time(scheduledAt)} زمان‌بندی شد.');
    }
  }

  Future<void> _scheduleSend() async {
    if (input.text.trim().isEmpty) {
      store.onNotice?.call('ابتدا متن پیام را بنویسید.');
      return;
    }
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context, initialDate: now, firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      helpText: 'انتخاب روز ارسال',
      cancelText: 'انصراف', confirmText: 'بعدی',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 15))),
      helpText: 'ساعت ارسال', cancelText: 'انصراف', confirmText: 'تأیید',
    );
    if (time == null || !mounted) return;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final gap = at.difference(DateTime.now());
    if (gap < const Duration(seconds: 10) || gap > const Duration(days: 30)) {
      store.onNotice?.call('زمان ارسال باید از ۱۰ ثانیه دیگر تا ۳۰ روز آینده باشد.');
      return;
    }
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('تأیید ارسال زمان‌دار'),
      content: Text('پیام در ساعت ${Jalali.time(at)} ثبت می‌شود. ممکن است اندروید یا اپراتور ارسال را به تأخیر بیندازد. در صورت نیاز از صفحه گفتگو لغو کنید.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('زمان‌بندی')),
      ],
    ));
    if (confirmed == true && mounted) await _send(scheduledAt: at);
  }

  Future<void> _templates() async {
    final text = await showTemplatesSheet(context, store, currentText: input.text);
    if (text != null) input.text = text;
  }

  Future<void> _emojiPicker() async {
    const emojis = ['😊', '🙏', '❤️', '🌹', '👍', '😂', '🎉', '✨', '💐', '👌', '🤝', '💚'];
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final emoji in emojis)
            InkWell(
              onTap: () {
                final value = input.value;
                final start = value.selection.isValid ? value.selection.start : value.text.length;
                final end = value.selection.isValid ? value.selection.end : value.text.length;
                final next = value.text.replaceRange(start, end, emoji);
                input.value = TextEditingValue(text: next,
                  selection: TextSelection.collapsed(offset: start + emoji.length));
                Navigator.pop(sheet);
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(padding: const EdgeInsets.all(10),
                child: Text(emoji, style: const TextStyle(fontSize: 26))),
            ),
        ]),
      )),
    );
  }

  Future<void> _polish() async {
    if (input.text.trim().isEmpty) {
      store.onNotice?.call('ابتدا متن پیام را بنویسید.');
      return;
    }
    final text = await showPolishSheet(context, input.text);
    if (text != null) input.text = text;
  }

  void _messageActions(MessageRecord m) {
    final pinnedHere = m.id != null && store.pinnedMessageId(widget.address) == m.id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('کپی متن'), onTap: () {
          Clipboard.setData(ClipboardData(text: m.body));
          Navigator.pop(ctx);
          store.onNotice?.call('متن کپی شد.');
        }),
        if (m.id != null)
          ListTile(
            leading: Icon(pinnedHere ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(pinnedHere ? 'برداشتن سنجاق پیام' : 'سنجاق پیام بالای گفتگو'),
            onTap: () {
              Navigator.pop(ctx);
              store.togglePinMessage(widget.address, m.id!);
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

  List<_Entry> _entries(List<MessageRecord> messages, List<PendingSend> pending) {
    final items = <_Entry>[for (final p in pending.reversed) _Entry(pending: p)];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      items.add(_Entry(message: m));
      final next = i + 1 < messages.length ? messages[i + 1] : null;
      if (next == null || !_sameDay(next.date, m.date)) items.add(_Entry(header: Jalali.dayHeader(m.date)));
    }
    return items;
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
        final items = _entries(messages, pending);
        final quickReplies = messages.isNotEmpty && !messages.first.outgoing &&
                MessageLogic.category(messages.first) == MessageCategory.personal
            ? SmartAssistant.suggestReplies(messages.first.body)
            : const <String>[];
        final pinned = store.isPinned(widget.address);
        final pinnedId = store.pinnedMessageId(widget.address);
        MessageRecord? pinnedMessage;
        if (pinnedId != null) {
          for (final m in messages) {
            if (m.id == pinnedId) {
              pinnedMessage = m;
              break;
            }
          }
        }
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(children: [
              SenderAvatar(name: name, address: widget.address, radius: 19,
                category: store.infoFor(widget.address)?.category ?? MessageCategory.personal),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
                if (name != widget.address)
                  Text(widget.address, textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant)),
              ])),
            ]),
            actions: [
              if (isPhone)
                IconButton(tooltip: 'تماس', icon: const Icon(Icons.call_outlined),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: SmsBridge.normalizeNumber(widget.address)))),
              IconButton(
                tooltip: pinned ? 'برداشتن سنجاق' : 'سنجاق کردن گفتگو',
                icon: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: pinned ? const Color(0xFFB8862E) : null),
                onPressed: () => store.togglePin(widget.address)),
              PopupMenuButton<String>(
                onSelected: _menu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy', child: Text('کپی شماره')),
                  PopupMenuItem(value: 'archive', child: Text(store.isArchived(widget.address) ? 'خارج کردن از بایگانی' : 'بایگانی')),
                  if (SmsBridge.supported) const PopupMenuItem(value: 'block', child: Text('مسدود کردن')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف گفتگو')),
                ]),
            ],
          ),
          body: Column(children: [
            if (pinnedMessage != null)
              Material(
                color: scheme.primaryContainer.withValues(alpha: .55),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.push_pin_rounded, size: 18, color: Color(0xFFB8862E)),
                  title: Text(pinnedMessage.body.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(tooltip: 'برداشتن سنجاق پیام', icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => store.togglePinMessage(widget.address, pinnedId!)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: pinnedMessage!.body));
                    store.onNotice?.call('متن پیام سنجاق‌شده کپی شد.');
                  },
                ),
              ),
            Expanded(child: items.isEmpty
                ? const EmptyState(icon: Icons.chat_outlined, title: 'هنوز پیامی نیست', subtitle: 'اولین پیام را بنویسید.')
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight, end: Alignment.bottomLeft,
                        colors: [scheme.primary.withValues(alpha: .055),
                          scheme.surfaceContainerLowest,
                          const Color(0xFFD6B779).withValues(alpha: .055)],
                      ),
                    ),
                    child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      if (e.header != null) return _DayHeader(e.header!);
                      final p = e.pending;
                      if (p != null) {
                        return TweenAnimationBuilder<double>(
                          key: ValueKey('queued-${p.id}'),
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.easeOutCubic,
                          tween: Tween(begin: 0, end: 1),
                          builder: (_, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 18 * (1 - value)), child: child)),
                          child: _Bubble(text: p.body, outgoing: true,
                            time: p.scheduled ? 'زمان‌دار • ${Jalali.time(p.deadline)}' : 'در صف ارسال'),
                        );
                      }
                      return _bubbleFor(e.message!, pinnedId);
                    }))),
            if (canReply && quickReplies.isNotEmpty)
              SizedBox(height: 45, child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final suggestion in quickReplies)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 7),
                      child: ActionChip(
                        avatar: Icon(Icons.auto_awesome_outlined, color: scheme.primary, size: 17),
                        label: Text(suggestion, style: const TextStyle(fontSize: 12)),
                        onPressed: () { input.text = suggestion; },
                      ),
                    ),
                ],
              )),
            if (canReply) _inputBar(scheme) else Padding(
              padding: const EdgeInsets.all(14),
              child: Text('امکان پاسخ به این فرستنده وجود ندارد.', style: TextStyle(color: scheme.onSurfaceVariant))),
          ]),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _bubbleFor(MessageRecord m, int? pinnedId) {
    String? status;
    if (m.outgoing) {
      status = m.type == 5
          ? 'ارسال نشد'
          : m.type == 4 || m.type == 6
              ? (DateTime.now().difference(m.date).inSeconds >= 25
                  ? 'در انتظار تأیید شبکه' : 'در حال ارسال')
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
      pinned: m.id != null && m.id == pinnedId,
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
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: input,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : Padding(padding: const EdgeInsets.only(bottom: 2), child: SmsCounter(text: value.text))),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Tooltip(
              message: 'ارسال (لمس طولانی: ارسال زمان‌دار)',
              child: SendControl(
                requests: store.pendingSends.where((p) => store.key(p.to) == store.key(widget.address)).toList(),
                sending: sending,
                onSend: () => _send(),
                onSchedule: _scheduleSend,
                onUndo: () async {
                  final pending = store.pendingSends.where(
                    (p) => store.key(p.to) == store.key(widget.address)).toList();
                  String? restore;
                  for (final p in pending) {
                    if (await store.undo(p)) restore ??= p.body;
                  }
                  if (restore != null && mounted) input.text = restore;
                },
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'ابزارهای پیام',
              icon: Icon(Icons.add_circle_outline_rounded, color: scheme.primary, size: 27),
              onSelected: (option) {
                if (option == 'templates') _templates();
                if (option == 'polish') _polish();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'templates', child: ListTile(
                  dense: true, leading: Icon(Icons.library_books_outlined), title: Text('پیام‌های آماده'))),
                PopupMenuItem(value: 'polish', child: ListTile(
                  dense: true, leading: Icon(Icons.auto_fix_high_rounded), title: Text('ویرایش متن'))),
              ],
            ),
            IconButton(tooltip: 'شکلک‌ها', onPressed: _emojiPicker,
              icon: Icon(Icons.sentiment_satisfied_alt_rounded, color: scheme.primary)),
            if (dualSim)
              PopupMenuButton<int>(
                tooltip: 'انتخاب سیم‌کارت',
                icon: Icon(Icons.sim_card_outlined, color: scheme.primary),
                onSelected: (v) => setState(() => store.selectedSim = v),
                itemBuilder: (_) => [
                  for (final sim in store.sims)
                    CheckedPopupMenuItem(
                      value: sim['id'] as int,
                      checked: store.selectedSim == sim['id'],
                      child: Text(sim['label'].toString())),
                ],
              ),
            Expanded(child: TextField(
              controller: input,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'پیام بنویسید…',
                counterText: '',
                filled: true,
                fillColor: scheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: scheme.outlineVariant)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: scheme.outlineVariant)),
              ),
            )),
            const SizedBox(width: 2),
          ]),
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
  final bool pinned;
  final String time;
  final Widget? trailing;
  final VoidCallback? onLongPress;
  const _Bubble({required this.text, required this.outgoing, required this.time,
    this.failed = false, this.warning = false, this.pinned = false, this.trailing, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = failed ? scheme.errorContainer
      : outgoing ? (dark ? const Color(0xFF174D4E) : const Color(0xFFD9EFEB))
      : (dark ? const Color(0xFF263A40) : Colors.white);
    final fg = failed ? scheme.onErrorContainer
      : outgoing && dark ? const Color(0xFFF1F8F6) : scheme.onSurface;
    const r = Radius.circular(20);
    return Align(
      alignment: outgoing ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: bg,
              boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .05), blurRadius: 6, offset: const Offset(0, 2))],
              border: pinned ? Border.all(color: const Color(0xFFD4A94E), width: 1.5) : null,
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
              Text(text.trim().isEmpty ? 'پیام بدون متن' : text.trim(),
                maxLines: 8, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 15.5, height: 1.7)),
              if (text.length > 260 || text.split('\n').length > 8)
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('متن کامل پیام'),
                      content: SizedBox(
                        width: MediaQuery.sizeOf(ctx).width * .85,
                        child: SingleChildScrollView(child: SelectableText(text.trim(),
                          style: const TextStyle(height: 1.8))),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx),
                          child: const Text('بستن')),
                      ],
                    ),
                  ),
                  child: const Text('نمایش متن کامل'),
                ),
              if (trailing != null) Padding(padding: const EdgeInsets.only(top: 6), child: trailing),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (pinned) Padding(padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Icon(Icons.push_pin_rounded, size: 12, color: fg.withValues(alpha: .7))),
                Text(time, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 11)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
