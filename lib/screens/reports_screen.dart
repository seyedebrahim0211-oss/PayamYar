import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../finance_logic.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../report_logic.dart';
import 'birthdays_screen.dart';
import 'widgets.dart';

/// On-device reports: bank balances and cash flow, message "tops" per period and categories.
/// Everything is computed in a background isolate (see AppStore.report).
class ReportsScreen extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  const ReportsScreen({super.key, required this.store, required this.settings});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod period = ReportPeriod.month;

  AppStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, widget.settings]),
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final hide = widget.settings.hidePreview;
        final report = store.report;
        final data = report.data;
        String money(int v) => hide ? '••••' : Jalali.digits(FinanceLogic.formatTomans(v));
        final byBank = <String, List<AccountBalance>>{};
        for (final b in data.balances) {
          (byBank[b.bank] ??= []).add(b);
        }
        final banks = byBank.keys.toList()
          ..sort((a, b) => FinanceLogic.totalBalance(byBank[b]!).compareTo(FinanceLogic.totalBalance(byBank[a]!)));
        final insight = data.periods[period];
        final title = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);
        return Scaffold(
          appBar: AppBar(
            title: const Text('گزارش‌ها'),
            actions: [
              IconButton(
                tooltip: 'تولد مخاطبین',
                icon: const Icon(Icons.cake_outlined),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => BirthdaysScreen(store: store))),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            if (store.reportPending && data.total == 0)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            // ── total balance hero ──
            _BalanceHero(
              total: money(data.totalBalance),
              accounts: data.balances.length,
              banks: banks.length,
              deposits: money(data.deposits),
              withdrawals: money(data.withdrawals),
              oldest: data.balances.isEmpty
                  ? null
                  : data.balances.map((b) => b.updatedAt).reduce((a, b) => a.isBefore(b) ? a : b),
            ),
            const SizedBox(height: 14),
            // ── per bank ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.account_balance_wallet_outlined, color: scheme.primary),
                    const SizedBox(width: 9),
                    Expanded(child: Text('تازه‌ترین موجودی هر حساب', style: title)),
                  ]),
                  const SizedBox(height: 4),
                  Text('از جدیدترین پیامک دارای موجودی هر حساب؛ موجودی تخمینی محاسبه نمی‌شود.',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  if (data.balances.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('هنوز پیامک بانکی دارای موجودی شناسایی نشده است.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  for (final bank in banks) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 14, bottom: 7),
                      child: Row(children: [
                        Icon(Icons.account_balance_rounded, color: scheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(bank, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(money(FinanceLogic.totalBalance(byBank[bank]!)),
                            style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary, fontSize: 12.5)),
                      ]),
                    ),
                    for (final b in byBank[bank]!) _AccountRow(balance: b, money: money),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 14),
            // ── monthly flow ──
            if (data.months.any((m) => m.deposits > 0 || m.withdrawals > 0))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('روند واریز و برداشت ۶ ماه اخیر', style: title),
                    const SizedBox(height: 14),
                    _MonthChart(months: data.months),
                    const SizedBox(height: 8),
                    Row(children: [
                      const _Legend(color: Color(0xFF2E9E6A), label: 'واریز'),
                      const SizedBox(width: 14),
                      _Legend(color: scheme.error, label: 'برداشت'),
                    ]),
                  ]),
                ),
              ),
            if (data.biggest.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('بزرگ‌ترین برداشت‌های ۳۰ روز اخیر', style: title),
                    ),
                    for (final e in data.biggest)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.north_east_rounded, color: scheme.error),
                        title: Text(FinanceLogic.bankOf(e.sender, '')),
                        subtitle: Text(Jalali.short(e.date)),
                        trailing: Text(money(e.amountTomans), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // ── tops per period ──
            Row(children: [
              Expanded(child: Text('برترین‌ها', style: Theme.of(context).textTheme.titleLarge)),
              SegmentedButton<ReportPeriod>(
                showSelectedIcon: false,
                segments: [
                  for (final p in ReportPeriod.values) ButtonSegment(value: p, label: Text(reportPeriodNames[p]!)),
                ],
                selected: {period},
                onSelectionChanged: (v) => setState(() => period = v.first),
              ),
            ]),
            const SizedBox(height: 12),
            if (insight == null)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
            else ...[
              Row(children: [
                Expanded(child: _Stat(label: 'دریافتی', value: insight.received, icon: Icons.call_received_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _Stat(label: 'ارسالی', value: insight.sent, icon: Icons.call_made_rounded)),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    label: 'تبلیغاتی',
                    value: insight.categories[MessageCategory.advertising] ?? 0,
                    icon: Icons.campaign_outlined,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              if (insight.topContacts.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('پرپیام‌ترین مخاطب‌ها', style: title),
                      ),
                      for (var i = 0; i < insight.topContacts.length; i++)
                        ListTile(
                          dense: true,
                          leading: _Rank(index: i),
                          title: Text(store.displayName(insight.topContacts[i].key)),
                          trailing: Text('${Jalali.digits(insight.topContacts[i].value)} پیام'),
                        ),
                    ]),
                  ),
                ),
              if (insight.topWords.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('پرتکرارترین کلمه‌ها', style: title),
                      const SizedBox(height: 4),
                      Text('از پیام‌های شخصی؛ فقط روی همین گوشی محاسبه می‌شود.',
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      _WordCloud(words: insight.topWords),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('زمان‌های پرپیام', style: title),
                    const SizedBox(height: 4),
                    Text(
                      'شلوغ‌ترین ساعت: ${Jalali.digits(insight.busiestHour)} • شلوغ‌ترین روز: ${weekdayNames[insight.busiestWeekday]}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    _HourChart(hours: insight.hours),
                    const SizedBox(height: 14),
                    for (var d = 0; d < 7; d++)
                      _Bar(label: weekdayNames[d], value: insight.weekdays[d],
                          max: insight.weekdays.reduce((a, b) => a > b ? a : b)),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('دسته‌بندی همه پیام‌ها', style: title),
                  const SizedBox(height: 12),
                  for (final c in MessageCategory.values)
                    _Bar(label: categoryName(c), value: data.counts[c] ?? 0, max: data.total),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'موجودی‌ها از متن آخرین پیامک هر حساب خوانده می‌شوند؛ برای مبلغ قطعی، سامانه رسمی بانک را بررسی کنید. همه پردازش‌ها فقط روی گوشی انجام می‌شود.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ]),
        );
      },
    );
  }
}

class _BalanceHero extends StatelessWidget {
  final String total;
  final int accounts;
  final int banks;
  final String deposits;
  final String withdrawals;
  final DateTime? oldest;
  const _BalanceHero({required this.total, required this.accounts, required this.banks, required this.deposits,
      required this.withdrawals, required this.oldest});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stale = oldest != null && DateTime.now().difference(oldest!).inDays > 30;
    final accountsText = Jalali.digits(accounts);
    final banksText = Jalali.digits(banks);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [scheme.primary, Color.lerp(scheme.primary, const Color(0xFF14213D), .55)!],
        ),
        boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: .28), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.savings_outlined, color: Colors.white70, size: 20),
          const SizedBox(width: 6),
          const Expanded(child: Text('جمع موجودی همه بانک‌ها', style: TextStyle(color: Colors.white70))),
          Text('$accountsText حساب • $banksText بانک', style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(total, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
        ),
        if (stale)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('برخی حساب‌ها بیش از ۳۰ روز است پیامک موجودی نداشته‌اند.',
                style: TextStyle(color: Color(0xFFFFE2A8), fontSize: 11.5)),
          ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Flow(label: 'واریز ۳۰ روز', value: deposits, icon: Icons.south_west_rounded, color: const Color(0xFF9BF0C2))),
          Expanded(child: _Flow(label: 'برداشت ۳۰ روز', value: withdrawals, icon: Icons.north_east_rounded, color: const Color(0xFFFFB4A6))),
        ]),
      ]),
    );
  }
}

class _Flow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Flow({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ]),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
      ]);
}

class _AccountRow extends StatelessWidget {
  final AccountBalance balance;
  final String Function(int) money;
  const _AccountRow({required this.balance, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = DateTime.now().difference(balance.updatedAt).inDays;
    final when = Jalali.short(balance.updatedAt);
    final age = days > 30 ? ' • قدیمی' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.primary.withValues(alpha: .10)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.credit_card_rounded, color: scheme.onPrimaryContainer, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(balance.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('به‌روز: $when$age',
                style: TextStyle(fontSize: 11, color: days > 30 ? scheme.error : scheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(money(balance.amountTomans),
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

class _MonthChart extends StatelessWidget {
  final List<MonthFlow> months;
  const _MonthChart({required this.months});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var peak = 1;
    for (final m in months) {
      if (m.deposits > peak) peak = m.deposits;
      if (m.withdrawals > peak) peak = m.withdrawals;
    }
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final m in months)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                _Column(height: 110 * m.deposits / peak, color: const Color(0xFF2E9E6A)),
                const SizedBox(width: 3),
                _Column(height: 110 * m.withdrawals / peak, color: scheme.error),
              ]),
              const SizedBox(height: 6),
              Text(m.label, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant), maxLines: 1),
            ]),
          ),
      ]),
    );
  }
}

class _Column extends StatelessWidget {
  final double height;
  final Color color;
  const _Column({required this.height, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 10,
        height: height < 2 ? 2 : height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
      );
}

class _HourChart extends StatelessWidget {
  final List<int> hours;
  const _HourChart({required this.hours});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = hours.reduce((a, b) => a > b ? a : b);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        SizedBox(
          height: 70,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var h = 0; h < 24; h++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: peak == 0 ? 2 : 2 + 66 * hours[h] / peak,
                    decoration: BoxDecoration(
                      color: Color.lerp(scheme.primaryContainer, scheme.primary, peak == 0 ? 0 : hours[h] / peak),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final h in const [0, 6, 12, 18, 23])
            Text(Jalali.digits(h), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

class _WordCloud extends StatelessWidget {
  final List<MapEntry<String, int>> words;
  const _WordCloud({required this.words});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = words.first.value;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final w in words)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Color.lerp(scheme.surfaceContainerHighest, scheme.primaryContainer, w.value / peak),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${w.key}  ${Jalali.digits(w.value)}',
              style: TextStyle(fontSize: 12 + 5 * w.value / peak, fontWeight: FontWeight.w700)),
        ),
    ]);
  }
}

class _Rank extends StatelessWidget {
  final int index;
  const _Rank({required this.index});

  @override
  Widget build(BuildContext context) {
    const medals = ['🥇', '🥈', '🥉'];
    if (index < 3) return Text(medals[index], style: const TextStyle(fontSize: 22));
    return CircleAvatar(radius: 13, child: Text(Jalali.digits(index + 1), style: const TextStyle(fontSize: 12)));
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const _Stat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(height: 6),
          Text(Jalali.digits(value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  const _Bar({required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: max == 0 ? 0 : value / max,
              minHeight: 10,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        SizedBox(width: 56, child: Text(Jalali.digits(value), textAlign: TextAlign.left)),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}
