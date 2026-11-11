import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../finance_logic.dart';
import '../jalali.dart';
import '../message_logic.dart';
import 'widgets.dart';

/// On-device summary: bank deposits/withdrawals found in SMS, message counts and top senders.
class ReportsScreen extends StatelessWidget {
  final AppStore store;
  final AppSettings settings;
  const ReportsScreen({super.key, required this.store, required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, settings]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final hide = settings.hidePreview;
        // Computed once per change of the inbox and cached in the store.
        final report = store.report;
        final recent = report.recent;
        final deposits = report.deposits;
        final withdrawals = report.withdrawals;
        String money(int v) => hide ? '••••' : Jalali.digits(FinanceLogic.formatTomans(v));
        final counts = report.counts;
        final top = report.top;
        return Scaffold(
          appBar: AppBar(title: const Text('گزارش‌ها')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, .35)!]),
                borderRadius: BorderRadius.circular(24)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('خلاصه مالی ۳۰ روز اخیر', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _money('واریز', money(deposits), Icons.south_west_rounded, const Color(0xFF9BF0C2))),
                  Expanded(child: _money('برداشت', money(withdrawals), Icons.north_east_rounded, const Color(0xFFFFB4A6))),
                ]),
                const SizedBox(height: 10),
                Text('${Jalali.digits(recent.length)} تراکنش از پیامک‌های بانکی شناسایی شد',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _stat(context, 'پیام‌ها', store.messages.length, Icons.mail_outline_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, 'گفتگوها', store.conversations.length, Icons.forum_outlined)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, 'خوانده‌نشده',
                store.unreadConversations, Icons.mark_email_unread_outlined)),
            ]),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('دسته‌بندی پیام‌ها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final c in MessageCategory.values) _bar(context, categoryName(c), counts[c]!, store.messages.length),
              ]))),
            const SizedBox(height: 16),
            if (recent.isNotEmpty)
              Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('تراکنش‌های اخیر', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  for (final e in recent.take(8))
                    ListTile(
                      dense: true,
                      leading: Icon(e.kind == FinanceKind.deposit ? Icons.south_west_rounded : Icons.north_east_rounded,
                        color: e.kind == FinanceKind.deposit ? Colors.green : scheme.error),
                      title: Text(store.displayName(e.sender)),
                      subtitle: Text(Jalali.short(e.date)),
                      trailing: Text(money(e.amountTomans), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ]))),
            if (recent.isNotEmpty) const SizedBox(height: 16),
            if (top.isNotEmpty)
              Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('بیشترین پیام‌ها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  for (final c in top)
                    ListTile(
                      dense: true,
                      leading: SenderAvatar(name: store.displayName(c.address), address: c.address,
                        category: store.categoryOf(c), radius: 18),
                      title: Text(store.displayName(c.address)),
                      trailing: Text('${Jalali.digits(c.count)} پیام'),
                    ),
                ]))),
            const SizedBox(height: 12),
            Text('همه محاسبات روی گوشی شما انجام می‌شود و هیچ پیامی به جایی ارسال نمی‌شود.',
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ]),
        );
      },
    );
  }

  Widget _money(String label, String value, IconData icon, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color)),
      ]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
    ]);

  Widget _stat(BuildContext context, String label, int value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
      Icon(icon, color: scheme.primary),
      const SizedBox(height: 6),
      Text(Jalali.digits(value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ])));
  }

  Widget _bar(BuildContext context, String label, int value, int total) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : value / total, minHeight: 10,
            backgroundColor: scheme.surfaceContainerHighest))),
        SizedBox(width: 56, child: Text(Jalali.digits(value), textAlign: TextAlign.left)),
      ]),
    );
  }
}
