import 'package:flutter/material.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../sms_groups.dart';
import 'group_conversation_screen.dart';

/// A collapsible, chat-like entry for saved SMS broadcasts in the inbox.
/// Its rows link to actual batch history, not inferred group conversations.
class GroupInboxSection extends StatelessWidget {
  final AppStore store;
  const GroupInboxSection({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final groups = store.smsGroups.groups;
    if (groups.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final ordered = groups.toList()..sort((a, b) {
      DateTime latest(SmsGroup g) {
        final batches = store.smsGroups.batchesFor(g.id);
        return batches.isEmpty ? g.createdAt : batches.first.createdAt;
      }
      return latest(b).compareTo(latest(a));
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: const PageStorageKey('payamyar-group-inbox'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [scheme.primary, scheme.primary.withValues(alpha: .74)],
              ),
              boxShadow: [BoxShadow(
                color: scheme.primary.withValues(alpha: .15),
                blurRadius: 9,
                offset: const Offset(0, 3),
              )],
            ),
            child: Icon(Icons.groups_2_rounded, color: scheme.onPrimary),
          ),
          title: const Text('پیام‌های گروهی',
              style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(
            '${Jalali.digits(groups.length)} گروه • برای مشاهدهٔ ارسال‌ها باز کنید',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          children: [
            for (final group in ordered)
              Builder(builder: (context) {
                final batches = store.smsGroups.batchesFor(group.id);
                final last = batches.isEmpty ? null : batches.first;
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Material(
                    color: scheme.primaryContainer.withValues(alpha: .32),
                    borderRadius: BorderRadius.circular(15),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      leading: Icon(Icons.forum_rounded, color: scheme.primary),
                      title: Text(group.name, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${Jalali.digits(group.recipients.length)} عضو • '
                        '${last == null ? 'هنوز ارسال نشده' : 'آخرین ثبت: ${Jalali.short(last.createdAt)}'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupConversationScreen(store: store, group: group),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
