import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../sms_bridge.dart';
import '../sms_groups.dart';
import 'compose_screen.dart';
import 'conversation_screen.dart';
import 'message_interactions.dart';

/// Broadcast SMS is NOT an RCS/MMS room. This screen displays only broadcasts
/// explicitly queued from this group, matched against real Android SMS rows.
/// Other personal messages are not mislabelled as group sends.
class GroupConversationScreen extends StatefulWidget {
  final AppStore store;
  final SmsGroup group;
  const GroupConversationScreen({super.key, required this.store, required this.group});

  @override
  State<GroupConversationScreen> createState() => _GroupConversationScreenState();
}

class _GroupRow {
  final String recipient;
  final String body;
  final DateTime date;
  final bool confirmed;
  final bool incoming;
  final bool privateMessage;
  const _GroupRow(this.recipient, this.body, this.date,
      {required this.confirmed, this.incoming = false, this.privateMessage = false});
}

class _BatchBody {
  final SmsGroupBatch batch;
  final String? text;
  const _BatchBody(this.batch, this.text);
}

class _GroupConversationScreenState extends State<GroupConversationScreen> {
  final Map<String, String> _names = {};
  late Future<List<_BatchBody>> _batchBodies;
  bool _showMemberHistory = false;

  AppStore get store => widget.store;
  SmsGroup get group {
    for (final item in store.smsGroups.groups) {
      if (item.id == widget.group.id) return item;
    }
    return widget.group;
  }
  String _key(String address) => SmsGroupStore.normalize(address);

  @override
  void initState() {
    super.initState();
    _showMemberHistory = store.smsGroups.batchesFor(widget.group.id).isEmpty;
    _loadHistory();
    store.smsGroups.addListener(_onGroupsChanged);
    _loadContactNames();
  }

  @override
  void dispose() {
    store.smsGroups.removeListener(_onGroupsChanged);
    super.dispose();
  }

  void _onGroupsChanged() {
    if (!mounted) return;
    setState(_loadHistory);
    _loadContactNames();
  }

  void _loadHistory() {
    _batchBodies = Future.wait([
      for (final batch in store.smsGroups.batchesFor(widget.group.id))
        store.smsGroups.batchBody(batch).then((text) => _BatchBody(batch, text)),
    ]);
  }

  Future<void> _loadContactNames() async {
    if (!store.permissions.contacts || group.recipients.isEmpty) return;
    try {
      final names = await SmsBridge.contactNames(group.recipients);
      if (!mounted) return;
      setState(() {
        for (final item in names.entries) {
          if (item.value.trim().isNotEmpty) {
            _names[_key(item.key)] = item.value.trim();
          }
        }
      });
    } catch (_) { /* Phonebook access is optional. */ }
  }

  String _displayName(String address) {
    final normalized = _key(address);
    final fromContacts = _names[normalized];
    if (fromContacts != null && fromContacts.isNotEmpty) return fromContacts;
    final exact = store.displayName(address);
    if (exact != address && exact.trim().isNotEmpty) return exact;
    for (final item in store.names.entries) {
      if (_key(item.key) == normalized && item.value.trim().isNotEmpty) return item.value;
    }
    return address;
  }

  List<_GroupRow> _timeline(List<_BatchBody> history) {
    final indexed = <String, List<MessageRecord>>{};
    for (final m in store.messages) {
      (indexed[_key(m.sender)] ??= []).add(m);
    }
    final output = <_GroupRow>[];
    final shownIncoming = <String>{};
    for (final entry in history) {
      if (entry.text == null || entry.text!.isEmpty) continue;
      final body = entry.text!;
      for (final sent in entry.batch.acceptedAt.entries) {
        final at = DateTime.fromMillisecondsSinceEpoch(sent.value);
        final records = indexed[_key(sent.key)] ?? const <MessageRecord>[];
        final candidates = records.where((m) => m.outgoing &&
          m.body.trim() == body.trim() &&
          !m.date.isBefore(at.subtract(const Duration(seconds: 30))) &&
          !m.date.isAfter(at.add(const Duration(minutes: 10)))).toList()
          ..sort((a, b) => a.date.difference(at).abs().compareTo(b.date.difference(at).abs()));
        if (candidates.isNotEmpty) {
          final actual = candidates.first;
          output.add(_GroupRow(sent.key, actual.body, actual.date, confirmed: true));
        } else {
          // Accepted into the queue != delivered to recipient. Show a truthful
          // unconfirmed state instead of a fabricated sent message.
          output.add(_GroupRow(sent.key, body, at, confirmed: false));
        }
        // Incoming messages are private and not inherently group replies.
        // Show only those following a logged broadcast, clearly distinguished.
        for (final m in records) {
          if (m.outgoing || m.date.isBefore(at) ||
              m.date.isAfter(at.add(const Duration(hours: 24)))) { continue; }
          final key = '${_key(m.sender)}|${m.id ?? m.date.millisecondsSinceEpoch}';
          if (shownIncoming.add(key)) {
            output.add(_GroupRow(sent.key, m.body, m.date,
              confirmed: true, incoming: true));
          }
        }
      }
    }
    output.sort((a, b) => b.date.compareTo(a.date));
    return output;
  }

  /// Personal messages stay labelled as private; historical SMS cannot be
  /// retroactively attributed to a group broadcast without a batch record.
  List<_GroupRow> _memberTimeline() {
    final members = group.recipients.map(_key).toSet();
    final rows = <_GroupRow>[
      for (final m in store.messages)
        if (members.contains(_key(m.sender)))
          _GroupRow(m.sender, m.body, m.date,
            confirmed: true, incoming: !m.outgoing, privateMessage: true),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return rows.take(300).toList(growable: false);
  }

  void _openChat(String number) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConversationScreen(store: store, address: number)));
  }

  void _compose() {
    // Keep the group conversation underneath the composer instead of
    // navigating to an unrelated recipient thread.
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .86,
        child: ComposeScreen(store: store,
          initialRecipients: group.recipients,
          initialGroupName: group.name,
          initialGroupId: group.id,
          createGroup: true, lockGroupRecipients: true),
      ),
    );
  }

  void _editMembers() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ComposeScreen(store: store,
        initialRecipients: group.recipients,
        initialGroupName: group.name,
        initialGroupId: group.id,
        createGroup: true)));
  }

  void _showMemberChats() {
    final members = group.recipients;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .72,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16),
            child: Text('گفتگوهای خصوصی اعضای گروه',
              style: Theme.of(sheet).textTheme.titleMedium)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('پیام‌های قدیمی هر عضو از همینجا قابل مشاهده‌اند؛ '
              'اما بدون سابقه ثبت ارسال گروهی، به‌اشتباه به گروه نسبت داده نمی‌شوند.',
              textAlign: TextAlign.center)),
          Expanded(child: ListView.builder(
            itemCount: members.length,
            itemBuilder: (_, index) {
              final number = members[index];
              final name = _displayName(number);
              final records = store.conversationFor(number)?.messages;
              final latest = records == null || records.isEmpty ? null : records.first;
              return ListTile(
                leading: CircleAvatar(child: Text(name.isEmpty ? '؟' :
                  String.fromCharCode(name.runes.first))),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(latest?.body ?? 'هنوز پیامی ثبت نشده',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () {
                  Navigator.pop(sheet);
                  _openChat(number);
                },
              );
            },
          )),
        ]),
      )),
    );
  }

  Widget _item(_GroupRow entry, ColorScheme scheme) {
    final name = _displayName(entry.recipient);
    final known = name != entry.recipient;
    final color = entry.incoming ? scheme.surfaceContainerHigh : scheme.primaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: scheme.primary.withValues(alpha: .1),
            child: Text(name.isEmpty ? '؟' : String.fromCharCode(name.runes.first),
              style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Material(
            color: color.withValues(alpha: .75),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openChat(entry.recipient),
              onLongPress: () => Clipboard.setData(ClipboardData(text: entry.body)),
              child: Padding(padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                      Icon(entry.incoming ? Icons.call_received_rounded :
                        entry.confirmed ? Icons.done_all_rounded : Icons.schedule_rounded,
                        size: 17, color: entry.confirmed ? scheme.primary : scheme.error),
                    ]),
                    if (known) Padding(padding: const EdgeInsets.only(top: 2),
                      child: Text(Jalali.digits(entry.recipient),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.labelSmall)),
                    const SizedBox(height: 8),
                    InteractiveMessageText(text: entry.body,
                      onPhoneMessage: _openChat),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Text(
                        entry.incoming ? 'پیام خصوصی دریافتی' :
                          entry.privateMessage ? 'پیام خصوصی ارسالی' :
                          entry.confirmed ? 'ثبت‌شده در پیامک‌های گوشی' :
                          'در صف قرار گرفت؛ ثبت نهایی در گوشی تأیید نشد',
                        style: Theme.of(context).textTheme.labelSmall)),
                      Text(Jalali.time(entry.date),
                        style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  ],
                )),
            ),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${Jalali.digits(group.recipients.length)} عضو',
            style: Theme.of(context).textTheme.labelSmall),
        ]),
        actions: [
          IconButton(tooltip: 'گفتگوهای خصوصی اعضا',
            icon: const Icon(Icons.people_outline_rounded), onPressed: _showMemberChats),
          IconButton(tooltip: 'مدیریت و افزودن مخاطب گروه',
            icon: const Icon(Icons.group_add_outlined), onPressed: _editMembers),
          IconButton(tooltip: 'ارسال به اعضای گروه',
            icon: const Icon(Icons.edit_square), onPressed: _compose),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .5),
              border: Border.all(color: scheme.primary.withValues(alpha: .15)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Icon(Icons.verified_user_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'هر پیام جداگانه برای یک مخاطب ارسال می‌شود. '
                'اینجا فقط ارسال‌های ثبت‌شده از همین گروه و پیام‌های خصوصی پس از آنها دیده می‌شوند؛ '
                'پاسخ‌ها گفتگوهای گروهی مشترک نیستند.',
                style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SizedBox(width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('ارسال‌های گروه')),
                ButtonSegment(value: true, label: Text('پیام‌های اعضا')),
              ],
              selected: {_showMemberHistory},
              onSelectionChanged: (selected) =>
                setState(() => _showMemberHistory = selected.first),
            )),
        ),
        Expanded(child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => FutureBuilder<List<_BatchBody>>(
            future: _batchBodies,
            builder: (context, snap) {
              if (!_showMemberHistory && snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = _showMemberHistory
                  ? _memberTimeline() : _timeline(snap.data ?? const <_BatchBody>[]);
              if (rows.isEmpty) {
                return Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text(_showMemberHistory
                    ? 'هنوز پیامک شخصی قابل نمایش برای اعضای این گروه در صندوق گوشی ثبت نشده است.'
                    : 'هنوز ارسال ثبت‌شده از این گروه وجود ندارد. پیام‌های شخصی را از تب پیام‌های اعضا ببینید.',
                    textAlign: TextAlign.center)));
              }
              return ListView.builder(
                reverse: true, itemCount: rows.length,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                itemBuilder: (context, i) => _item(rows[i], scheme),
              );
            },
          ),
        )),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.send_rounded),
              label: const Text('ارسال پیام به اعضای گروه'),
              onPressed: _compose)))),
      ]),
    );
  }
}
