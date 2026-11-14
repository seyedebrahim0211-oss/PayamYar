import 'package:flutter/material.dart';
import '../app_store.dart';
import '../jalali.dart';
import '../sms_groups.dart';
import 'compose_screen.dart';
import 'conversation_screen.dart';
import 'group_conversation_screen.dart';

/// Local SMS broadcast lists. Replies remain in each recipient's private thread.
class GroupsScreen extends StatelessWidget {
  final AppStore store;
  const GroupsScreen({super.key, required this.store});

  Future<void> _delete(BuildContext context, SmsGroup group) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('حذف گروه پیامکی'),
        content: Text('گروه «${group.name}» حذف شود؟ پیام‌های خصوصی اعضا حذف نمی‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف گروه')),
        ],
      ));
    if (confirmed == true) await store.smsGroups.remove(group.id);
  }

  void _compose(BuildContext context, {SmsGroup? group}) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComposeScreen(
      store: store, initialRecipients: group?.recipients,
      initialGroupName: group?.name, initialGroupId: group?.id,
      createGroup: true,
    )));
  }

  void _members(BuildContext context, SmsGroup group) {
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .7,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(14), child: Text(
            '${group.name} · ${Jalali.digits(group.recipients.length)} مخاطب',
            style: Theme.of(ctx).textTheme.titleMedium)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text('پاسخ هر نفر فقط در گفتگوی خصوصی همان مخاطب نمایش داده می‌شود.',
              textAlign: TextAlign.center)),
          Expanded(child: ListView.builder(
            itemCount: group.recipients.length,
            itemBuilder: (_, index) {
              final number = group.recipients[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                title: Text(store.displayName(number)),
                subtitle: Text(number, textDirection: TextDirection.ltr),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => ConversationScreen(store: store, address: number)));
                },
              );
            },
          )),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store.smsGroups,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('گروه‌های پیامکی'),
          actions: [
            IconButton(tooltip: 'ساخت گروه', icon: const Icon(Icons.group_add_rounded),
              onPressed: () => _compose(context)),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                scheme.primaryContainer,
                scheme.primaryContainer.withValues(alpha: .3),
              ]),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: scheme.primary.withValues(alpha: .15)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.groups_2_outlined, color: scheme.primary, size: 30),
                const SizedBox(width: 12),
                Expanded(child: Text('ارسال یک متن به چند مخاطب',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 8),
              const Text('گروه پیامکی فقط یک فهرست ذخیره‌شده از شماره‌هاست؛ '
                'برای حفظ حریم خصوصی، پیام هر عضو جداگانه ارسال می‌شود و پاسخ او در صفحه شخصی خودش می‌آید.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _compose(context),
                icon: const Icon(Icons.group_add_rounded),
                label: const Text('ساخت گروه پیامکی جدید')),
            ]),
          ),
          const SizedBox(height: 18),
          if (store.smsGroups.groups.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(children: [
                Icon(Icons.groups_outlined, size: 54, color: scheme.primary.withValues(alpha: .45)),
                const SizedBox(height: 12),
                const Text('هنوز گروه پیامکی ذخیره نشده است'),
              ])),
          for (final group in store.smsGroups.groups)
            Card(clipBehavior: Clip.antiAlias, margin: const EdgeInsets.only(bottom: 11),
              child: Column(children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  leading: CircleAvatar(backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.groups_rounded, color: scheme.primary)),
                  title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${Jalali.digits(group.recipients.length)} عضو · ارسال خصوصی برای هر شماره'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'مدیریت گروه',
                    onSelected: (choice) {
                      if (choice == 'members') _members(context, group);
                      if (choice == 'delete') _delete(context, group);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'members', child: Text('فهرست اعضا و گفتگوهای خصوصی')),
                      PopupMenuItem(value: 'delete', child: Text('حذف گروه')),
                    ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => GroupConversationScreen(store: store, group: group))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                  child: SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
                    onPressed: () => _compose(context, group: group),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('ارسال پیام گروهی (جداگانه برای هر نفر)'),
                  )),
                ),
              ])),
        ]),
      ),
    );
  }
}
