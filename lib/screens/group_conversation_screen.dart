import 'package:flutter/material.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../sms_groups.dart';
import 'compose_screen.dart';
import 'conversation_screen.dart';

/// One local timeline for a broadcast list. This is NOT a shared SMS/RCS room.
/// Every incoming reply remains private to its sender; the group view only
/// aggregates messages already stored on this phone.
class GroupConversationScreen extends StatelessWidget {
  final AppStore store;
  final SmsGroup group;
  const GroupConversationScreen({super.key, required this.store, required this.group});

  @override
  Widget build(BuildContext context) {
    final recipients = group.recipients.map(SmsGroupStore.normalize).toSet();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          IconButton(
            tooltip: 'ارسال به اعضای گروه',
            icon: const Icon(Icons.edit_square),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => ComposeScreen(store: store, initialRecipients: group.recipients,
                initialGroupName: group.name, initialGroupId: group.id, createGroup: true),
            )),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final messages = store.messages.where(
            (m) => recipients.contains(SmsGroupStore.normalize(m.sender)),
          ).toList()..sort((a, b) => b.date.compareTo(a.date));
          return Column(children: [
            Material(
              color: scheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.info_outline, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'نمای تجمیعی پیام‌های اعضای گروه؛ هر پیامک جداگانه ارسال می‌شود و پاسخ‌ها خصوصی هستند.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                ]),
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text('هنوز پیامی از اعضای این گروه در گوشی ثبت نشده است.'))
                  : ListView.builder(
                      reverse: true,
                      itemCount: messages.length,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        return Align(
                          alignment: m.outgoing ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Card(
                              color: m.outgoing ? scheme.primaryContainer : scheme.surfaceContainerLow,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                                  builder: (_) => ConversationScreen(store: store, address: m.sender),
                                )),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(store.displayName(m.sender),
                                      style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
                                    const SizedBox(height: 5),
                                    Text(m.body),
                                    const SizedBox(height: 6),
                                    Text(Jalali.time(m.date), style: Theme.of(context).textTheme.labelSmall),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(width: double.infinity, child: FilledButton.icon(
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('نوشتن پیام برای گروه'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => ComposeScreen(store: store, initialRecipients: group.recipients,
                      initialGroupName: group.name, initialGroupId: group.id, createGroup: true),
                  )),
                )),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
