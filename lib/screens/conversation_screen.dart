import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../chat_theme.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../sms_bridge.dart';
import '../smart_assistant.dart';
import '../conversation_insights.dart';
import 'compose_screen.dart';
import 'compose_tools.dart';
import 'send_control.dart';
import 'home_screen.dart';
import 'widgets.dart';

class ConversationScreen extends StatefulWidget {
  final AppStore store;
  final String address;
  /// Draft placed in the composer, e.g. from an sms: link or the phone's Contacts app.
  final String initialText;
  const ConversationScreen({super.key, required this.store, required this.address, this.initialText = ''});
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
  late final input = TextEditingController(text: widget.initialText);
  final focus = FocusNode();
  bool sending = false;
  AppStore get store => widget.store;
  static final _fallbackSettings = AppSettings();
  AppSettings get settings => store.settings ?? _fallbackSettings;

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
    focus.dispose();
    super.dispose();
  }

  Future<void> _send({DateTime? scheduledAt}) async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    final pending = await store.send(widget.address, text, scheduledAt: scheduledAt);
    if (!mounted) return;
    setState(() => sending = false);
    if (pending != null || !store.android) {
      input.clear();
      HapticFeedback.selectionClick();
    }
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

  Future<void> _showInsights() async {
    final messages = store.conversationFor(widget.address)?.messages ?? const <MessageRecord>[];
    final summary = ConversationInsights.summarize(messages);
    final tasks = ConversationInsights.actionItems(messages);
    final warnings = ConversationInsights.securityWarnings(messages);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: FractionallySizedBox(
        heightFactor: .72,
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Text('دستیار آفلاین گفتگو', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('تحلیل قاعده‌محور روی همین گوشی؛ هیچ پیامکی ارسال یا به سرور منتقل نمی‌شود. این تحلیل ممکن است دقیق نباشد.'),
          const SizedBox(height: 16),
          Text('مرور پیام‌های اخیر', style: Theme.of(ctx).textTheme.titleMedium),
          SelectableText(summary),
          const SizedBox(height: 16),
          Text('موارد قابل پیگیری', style: Theme.of(ctx).textTheme.titleMedium),
          if (tasks.isEmpty) const Text('مورد مشخصی پیدا نشد.'),
          for (final item in tasks) ListTile(dense: true, leading: const Icon(Icons.task_alt_rounded),
            title: Text(item),
            trailing: IconButton(icon: const Icon(Icons.copy_outlined),
              onPressed: () => Clipboard.setData(ClipboardData(text: item)))),
          const SizedBox(height: 12),
          Text('هشدارهای امنیتی', style: Theme.of(ctx).textTheme.titleMedium),
          if (warnings.isEmpty) const Text('الگوی مشکوک آشکاری شناسایی نشد؛ این نتیجه تأیید امنیت پیام نیست.'),
          for (final warning in warnings) ListTile(dense: true,
            leading: const Icon(Icons.gpp_maybe_outlined), title: Text(warning)),
        ]),
      )),
    );
  }

  Future<void> _templates() async {
    final text = await showTemplatesSheet(context, store, currentText: input.text);
    if (text != null) input.text = text;
  }

  Future<void> _emojiPicker() async {
    const emojis = ['😊', '🙏', '❤️', '🌹', '👍', '😂', '🎉', '✨', '💐', '👌', '🤝', '💚',
      '😍', '🤲', '🌸', '☕', '🎂', '🕊️', '🌙', '⭐', '💯', '🙌', '😅', '🤔'];
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

  /// A queued copy is shown only until Android's real outbox row takes its place,
  /// so a sent message never appears twice ("در صف ارسال" + "در حال ارسال").
  bool _stillLocal(PendingSend p, List<MessageRecord> messages, DateTime now) {
    if (p.deadline.isAfter(now)) return true;
    if (now.difference(p.deadline) > const Duration(seconds: 4)) return false;
    final from = p.deadline.subtract(const Duration(seconds: 20));
    for (final m in messages.take(30)) {
      if (m.outgoing && m.body.trim() == p.body.trim() && m.date.isAfter(from)) return false;
    }
    return true;
  }

  List<_Entry> _entries(List<MessageRecord> messages, List<PendingSend> pending) {
    final now = DateTime.now();
    final items = <_Entry>[
      for (final p in pending.reversed)
        if (_stillLocal(p, messages, now)) _Entry(pending: p),
    ];
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
      listenable: Listenable.merge([store, settings]),
      builder: (context, _) {
        final look = ChatLook.of(settings.chatStyle, scheme);
        final c = store.conversationFor(widget.address);
        final messages = c?.messages ?? const <MessageRecord>[];
        final name = store.displayName(widget.address);
        final key = store.key(widget.address);
        final pending = store.pendingSends.where((p) => store.key(p.to) == key).toList();
        final items = _entries(messages, pending);
        final quickReplies = settings.smartReplies && messages.isNotEmpty && !messages.first.outgoing &&
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
              SenderAvatar(name: name, address: widget.address, radius: 20,
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
                onSelected: (v) {
                  if (v == 'style') { _stylePicker(); }
                  else if (v == 'insights') { _showInsights(); }
                  else { _menu(v); }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'style', child: Text('قالب گفتگو')),
                  const PopupMenuItem(value: 'insights', child: Text('دستیار هوشمند آفلاین')),
                  const PopupMenuItem(value: 'copy', child: Text('کپی شماره')),
                  PopupMenuItem(value: 'archive', child: Text(store.isArchived(widget.address) ? 'خارج کردن از بایگانی' : 'بایگانی')),
                  if (SmsBridge.supported) const PopupMenuItem(value: 'block', child: Text('مسدود کردن')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف گفتگو')),
                ]),
            ],
          ),
          body: DecoratedBox(
            decoration: look.background,
            child: CustomPaint(
              painter: look.pattern,
              child: Column(children: [
                if (pinnedMessage != null)
                  Material(
                    color: scheme.primaryContainer.withValues(alpha: .7),
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
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          if (e.header != null) return _DayHeader(e.header!, look: look);
                          final p = e.pending;
                          if (p != null) {
                            return TweenAnimationBuilder<double>(
                              key: ValueKey('queued-${p.id}'),
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                              tween: Tween(begin: 0, end: 1),
                              builder: (_, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(offset: Offset(0, 18 * (1 - value)), child: child)),
                              child: _Bubble(text: p.body, outgoing: true, look: look, textSize: settings.bubbleText,
                                status: p.scheduled ? 'زمان‌دار • ${Jalali.time(p.deadline)}' : 'در صف ارسال',
                                statusIcon: p.scheduled ? Icons.schedule_rounded : Icons.access_time_rounded,
                                time: ''),
                            );
                          }
                          return _bubbleFor(e.message!, pinnedId, look);
                        })),
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
                if (canReply) _inputBar(scheme, look) else Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: scheme.surface.withValues(alpha: .85),
                  child: Text('این فرستنده پاسخ پیامکی دریافت نمی‌کند.', textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant))),
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _stylePicker() async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheet) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('قالب گفتگو', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (final style in ChatStyle.values)
                Padding(padding: const EdgeInsetsDirectional.only(end: 10),
                  child: ChatStylePreview(style: style, selected: settings.chatStyle == style,
                    onTap: () => settings.update(chatStyle: style))),
            ])),
            const SizedBox(height: 10),
            Text('اندازه متن حباب‌ها: ${Jalali.digits(settings.bubbleText.round())}'),
            Slider(value: settings.bubbleText, min: 13, max: 20, divisions: 14,
              onChanged: (v) => settings.update(bubbleText: v)),
          ]),
        )),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _bubbleFor(MessageRecord m, int? pinnedId, ChatLook look) {
    String? status;
    IconData? icon;
    if (m.outgoing) {
      if (m.type == 5) {
        status = 'ارسال نشد'; icon = Icons.error_outline_rounded;
      } else if (m.type == 4 || m.type == 6) {
        final waiting = DateTime.now().difference(m.date).inSeconds >= 25;
        status = waiting ? 'در انتظار تأیید شبکه' : 'در حال ارسال';
        icon = Icons.access_time_rounded;
      } else if (m.type == 3) {
        status = 'پیش‌نویس'; icon = Icons.edit_note_rounded;
      } else if (m.delivery == 0) {
        status = 'تحویل شد'; icon = Icons.done_all_rounded;
      } else if (m.delivery >= 64) {
        status = 'تحویل ناموفق'; icon = Icons.report_gmailerrorred_rounded;
      } else {
        status = 'ارسال شد'; icon = Icons.done_rounded;
      }
    }
    final code = m.outgoing ? null : MessageLogic.otp(m.body);
    return _Bubble(
      text: m.body,
      outgoing: m.outgoing,
      look: look,
      textSize: settings.bubbleText,
      failed: m.type == 5,
      pinned: m.id != null && m.id == pinnedId,
      warning: !m.outgoing && MessageLogic.suspicious(m.body),
      time: Jalali.time(m.date),
      status: status,
      statusIcon: icon,
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

  void _insert(String value) {
    final v = input.value;
    final start = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    input.value = TextEditingValue(text: v.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length));
  }

  Widget _inputBar(ColorScheme scheme, ChatLook look) {
    final dualSim = store.sims.length > 2;
    final pendingHere = store.pendingSends.where((p) => store.key(p.to) == store.key(widget.address)).toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: input,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : Padding(padding: const EdgeInsets.only(bottom: 3), child: SmsCounter(text: settings.withSignature(value.text)))),
          // Send button on the right edge (LTR order for this row only; the composer stays RTL).
          Row(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Composer pill: tools inside, typing area in the middle.
            Expanded(child: AnimatedBuilder(
              animation: focus,
              builder: (context, child) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: look.composer.copyWith(
                  border: focus.hasFocus ? Border.all(color: scheme.primary, width: 1.6) : look.composer.border,
                  boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: focus.hasFocus ? .14 : .05),
                    blurRadius: 14, offset: const Offset(0, 4))]),
                child: child),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(tooltip: 'شکلک‌ها', onPressed: _emojiPicker,
                  icon: Icon(Icons.emoji_emotions_outlined, color: scheme.primary)),
                Expanded(child: TextField(
                  controller: input,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 6,
                  maxLength: 2000,
                  style: TextStyle(fontSize: settings.bubbleText),
                  textInputAction: settings.enterToSend ? TextInputAction.send : TextInputAction.newline,
                  onSubmitted: settings.enterToSend ? (_) => _send() : null,
                  decoration: const InputDecoration(
                    hintText: 'پیام بنویسید…',
                    counterText: '',
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                )),
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
                PopupMenuButton<String>(
                  tooltip: 'ابزارهای پیام',
                  icon: Icon(Icons.add_circle_outline_rounded, color: scheme.primary),
                  onSelected: (option) {
                    switch (option) {
                      case 'templates': _templates();
                      case 'polish': _polish();
                      case 'schedule': _scheduleSend();
                      case 'signature': if (settings.signature.isNotEmpty) _insert('\n${settings.signature}');
                      case 'paste':
                        Clipboard.getData('text/plain').then((d) { if (d?.text != null) _insert(d!.text!); });
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'templates', child: ListTile(
                      dense: true, leading: Icon(Icons.library_books_outlined), title: Text('پیام‌های آماده'))),
                    const PopupMenuItem(value: 'polish', child: ListTile(
                      dense: true, leading: Icon(Icons.auto_fix_high_rounded), title: Text('ویرایش و مرتب‌سازی متن'))),
                    const PopupMenuItem(value: 'schedule', child: ListTile(
                      dense: true, leading: Icon(Icons.schedule_send_rounded), title: Text('ارسال زمان‌دار'))),
                    const PopupMenuItem(value: 'paste', child: ListTile(
                      dense: true, leading: Icon(Icons.content_paste_rounded), title: Text('چسباندن'))),
                    if (settings.signature.isNotEmpty && !settings.signatureEnabled)
                      const PopupMenuItem(value: 'signature', child: ListTile(
                        dense: true, leading: Icon(Icons.draw_outlined), title: Text('افزودن امضا'))),
                  ],
                ),
              ]),
            )),
            const SizedBox(width: 6),
            Tooltip(
              message: 'ارسال (لمس طولانی: ارسال زمان‌دار)',
              child: SendControl(
                requests: pendingHere,
                sending: sending,
                onSend: () => _send(),
                onSchedule: _scheduleSend,
                onUndo: () async {
                  final list = store.pendingSends.where(
                    (p) => store.key(p.to) == store.key(widget.address) && !p.scheduled).toList();
                  String? restore;
                  for (final p in list) {
                    if (await store.undo(p)) restore ??= p.body;
                  }
                  if (restore != null && mounted) {
                    final sig = settings.signature;
                    final text = settings.signatureEnabled && sig.isNotEmpty && restore.endsWith('\n$sig')
                        ? restore.substring(0, restore.length - sig.length - 1) : restore;
                    input.text = text;
                    input.selection = TextSelection.collapsed(offset: text.length);
                  }
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  final ChatLook look;
  const _DayHeader(this.label, {required this.look});
  @override
  Widget build(BuildContext context) => Center(child: Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: look.dayChip,
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: look.dayInk)),
  ));
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool outgoing;
  final bool failed;
  final bool warning;
  final bool pinned;
  final String time;
  final String? status;
  final IconData? statusIcon;
  final ChatLook look;
  final double textSize;
  final Widget? trailing;
  final VoidCallback? onLongPress;
  const _Bubble({required this.text, required this.outgoing, required this.time, required this.look,
    this.textSize = 15.5, this.status, this.statusIcon,
    this.failed = false, this.warning = false, this.pinned = false, this.trailing, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final fg = look.ink(outgoing, failed);
    final r = Radius.circular(look.radius);
    final base = look.bubble(outgoing, failed);
    final delivered = statusIcon == Icons.done_all_rounded;
    return Align(
      alignment: outgoing ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3.5),
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
            decoration: base.copyWith(
              border: pinned ? Border.all(color: const Color(0xFFD4A94E), width: 1.6) : base.border,
              borderRadius: BorderRadiusDirectional.only(
                topStart: r, topEnd: r,
                bottomStart: outgoing ? r : const Radius.circular(5),
                bottomEnd: outgoing ? const Radius.circular(5) : r,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (warning)
                InkWell(
                  onTap: () {
                    final reasons = MessageLogic.risk(text).reasons;
                    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
                      icon: const Icon(Icons.gpp_maybe_rounded, color: Colors.orange, size: 36),
                      title: const Text('چرا این پیام مشکوک است؟'),
                      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final r in reasons) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $r')),
                        const SizedBox(height: 6),
                        const Text('روی لینک نزنید، کد یا رمز کارت وارد نکنید و برنامه‌ای از لینک نصب نکنید. '
                          'برای پیگیری، مستقیم به سایت یا برنامه رسمی بروید.', style: TextStyle(fontSize: 12.5, height: 1.7)),
                      ]),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('متوجه شدم'))],
                    ));
                  },
                  child: const Padding(padding: EdgeInsets.only(bottom: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                    SizedBox(width: 4),
                    Flexible(child: Text('احتمال کلاهبرداری؛ روی لینک نزنید (جزئیات)', style: TextStyle(fontSize: 12, color: Colors.orange))),
                  ])),
                ),
              Text(text.trim().isEmpty ? 'پیام بدون متن' : text.trim(),
                maxLines: 8, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: textSize, height: 1.7)),
              if (text.length > 260 || text.split('\n').length > 8)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: fg, padding: EdgeInsets.zero),
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
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
                      ],
                    ),
                  ),
                  child: const Text('نمایش متن کامل'),
                ),
              if (trailing != null) Padding(padding: const EdgeInsets.only(top: 6), child: trailing),
              const SizedBox(height: 3),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (pinned) Padding(padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Icon(Icons.push_pin_rounded, size: 12, color: fg.withValues(alpha: .7))),
                if (time.isNotEmpty)
                  Text(time, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 11)),
                if (status != null) ...[
                  if (time.isNotEmpty) const SizedBox(width: 6),
                  if (statusIcon != null)
                    Icon(statusIcon, size: 14, color: delivered ? const Color(0xFF7FD3FF) : fg.withValues(alpha: .75)),
                  const SizedBox(width: 3),
                  Text(status!, style: TextStyle(color: fg.withValues(alpha: .75), fontSize: 11)),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
