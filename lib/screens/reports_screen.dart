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
        final byBank = <String, List<AccountBalance>>{};
        for (final balance in report.balances) {
          (byBank[balance.bank] ??= []).add(balance);
        }
        final bankNames = byBank.keys.toList()..sort();
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
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.account_balance_wallet_outlined, color: scheme.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Text('آخرین موجودی هر حساب',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 5),
                Text('فقط موجودی صریح در پیامک بانکی نمایش داده می‌شود؛ نه موجودی تخمینی.',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                if (report.balances.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Text('هنوز پیامک دارای موجودی و واحد پول شناسایی نشده است.',
                      style: TextStyle(color: scheme.onSurfaceVariant))),
                for (final bank in bankNames) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 13, bottom: 7),
                    child: Row(children: [
                      Icon(Icons.account_balance_rounded, color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(bank, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text('${Jalali.digits(byBank[bank]!.length)} حساب',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                  for (final balance in byBank[bank]!)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: scheme.primary.withValues(alpha: .10))),
                      child: Row(children: [
                        CircleAvatar(radius: 18, backgroundColor: scheme.primaryContainer,
                          child: Icon(Icons.credit_card_rounded, color: scheme.onPrimaryContainer, size: 18)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(balance.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('آخرین اعلام: ${Jalali.short(balance.updatedAt)}',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        ])),
                        const SizedBox(width: 7),
                        Flexible(child: Text(money(balance.amountTomans),
                          textAlign: TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary, fontSize: 12))),
                      ]),
                    ),
                ],
              ]),
            )),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _stat(context, 'پیام‌ها', store.messages.length, Icons.mail_outline_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, 'گفتگوها', store.conversations.length, Icons.forum_outlined)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, 'خوانده‌نشده',
                store.unreadConversations, Icons.mark_email_unread_outlined)),
            ]),
            const SizedBox(height: 11),
            Row(children: [
              Expanded(child: _stat(context, 'بانک‌ها', byBank.length, Icons.account_balance_outlined)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, 'حساب‌ها', report.balances.length, Icons.credit_card_outlined)),
              const SizedBox(width: 10),
              Expanded(child: _stat(context, 'تبلیغاتی',
                counts[MessageCategory.advertising] ?? 0, Icons.campaign_outlined)),
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
            Text('موجودی‌ها براساس متن آخرین پیامک هر حساب‌اند و ممکن است قدیمی یا نامعتبر باشند؛ برای موجودی قطعی، برنامه یا سامانه رسمی بانک را بررسی کنید. پردازش پیامک فقط روی گوشی انجام می‌شود.',
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
