import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../contacts/contacts_data.dart' show ContactsBridge;
import '../csv_util.dart';
import '../finance_logic.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../report_logic.dart';
import '../sms_bridge.dart';
import 'birthdays_screen.dart';
import 'widgets.dart';

const _green = Color(0xFF2E9E6A);
const _catColors = {
  MessageCategory.personal: Color(0xFF087F81),
  MessageCategory.banking: Color(0xFF305F91),
  MessageCategory.service: Color(0xFFA17A37),
  MessageCategory.advertising: Color(0xFFC0583B),
};

/// On-device reports dashboard: period KPIs with comparison, smart analysis, trends,
/// money per bank, balances, categories, tops and busy times. Shareable as text/CSV.
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
  bool allTransactions = false;

  AppStore get store => widget.store;

  String _money(int v) => widget.settings.hidePreview ? '••••' : Jalali.digits(FinanceLogic.formatTomans(v));

  Future<void> _share(ReportResult data, PeriodInsight p) async {
    final text = reportAsText(data, p, period, nameOf: store.displayName, money: _money);
    final ok = await SmsBridge.shareText(text, subject: 'گزارش پیامیار', title: 'ارسال گزارش');
    if (!ok) store.onNotice?.call('اشتراک‌گذاری در دسترس نیست.');
  }

  Future<void> _exportCsv(PeriodInsight p) async {
    if (p.transactions.isEmpty) {
      store.onNotice?.call('در این بازه تراکنش بانکی پیدا نشد.');
      return;
    }
    final now = DateTime.now();
    final j = Jalali.fromGregorian(now.year, now.month, now.day);
    final ok = await ContactsBridge.saveFile('تراکنش‌های-پیامیار-${j[0]}-${j[1]}-${j[2]}.csv', 'text/csv',
        csvBytes(transactionsAsRows(p.transactions)));
    if (ok) store.onNotice?.call('فایل تراکنش‌ها ذخیره شد (قابل باز کردن در اکسل).');
  }

  Future<void> _block(String sender) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسدود کردن فرستنده'),
        content: Text('پیام‌های «$sender» دیگر دریافت نشود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسدود کن')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SmsBridge.block(sender);
      store.onNotice?.call('«$sender» مسدود شد.');
    } catch (e) {
      store.onNotice?.call('مسدود کردن ممکن نشد؛ پیامیار باید پیامک‌رسان پیش‌فرض باشد.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, widget.settings]),
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final data = store.report.data;
        final p = data.periods[period];
        final byBank = <String, List<AccountBalance>>{};
        for (final b in data.balances) {
          (byBank[b.bank] ??= []).add(b);
        }
        final banks = byBank.keys.toList()
          ..sort((a, b) => FinanceLogic.totalBalance(byBank[b]!).compareTo(FinanceLogic.totalBalance(byBank[a]!)));
        return Scaffold(
          appBar: AppBar(
            title: const Text('گزارش‌ها'),
            actions: [
              if (p != null)
                IconButton(tooltip: 'اشتراک گزارش', icon: const Icon(Icons.ios_share_rounded), onPressed: () => _share(data, p)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'csv' && p != null) _exportCsv(p);
                  if (v == 'birthdays') {
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BirthdaysScreen(store: store)));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'csv', child: ListTile(dense: true, leading: Icon(Icons.table_view_rounded), title: Text('خروجی اکسل تراکنش‌ها'))),
                  PopupMenuItem(value: 'birthdays', child: ListTile(dense: true, leading: Icon(Icons.cake_outlined), title: Text('تولد مخاطبین'))),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            SegmentedButton<ReportPeriod>(
              showSelectedIcon: false,
              segments: [for (final x in ReportPeriod.values) ButtonSegment(value: x, label: Text(reportPeriodNames[x]!))],
              selected: {period},
              onSelectionChanged: (v) => setState(() {
                period = v.first;
                allTransactions = false;
              }),
            ),
            const SizedBox(height: 12),
            if (store.reportPending && data.total == 0)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            _BalanceHero(
              total: _money(data.totalBalance),
              accounts: data.balances.length,
              banks: banks.length,
              oldest: data.balances.isEmpty ? null : data.balances.map((b) => b.updatedAt).reduce((a, b) => a.isBefore(b) ? a : b),
            ),
            const SizedBox(height: 12),
            if (p == null)
              const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else ...[
              // ── KPIs with comparison to the previous period ──
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.75,
                children: [
                  _Kpi(label: 'پیام دریافتی', value: Jalali.digits(p.received), icon: Icons.call_received_rounded,
                      change: percentChange(p.received, p.prevReceived), color: scheme.primary),
                  _Kpi(label: 'پیام ارسالی', value: Jalali.digits(p.sent), icon: Icons.call_made_rounded,
                      change: percentChange(p.sent, p.prevSent), color: const Color(0xFF75539A)),
                  _Kpi(label: 'واریز', value: _money(p.deposits), icon: Icons.south_west_rounded,
                      change: percentChange(p.deposits, p.prevDeposits), color: _green),
                  _Kpi(label: 'برداشت', value: _money(p.withdrawals), icon: Icons.north_east_rounded,
                      change: percentChange(p.withdrawals, p.prevWithdrawals), color: scheme.error, upIsBad: true),
                ],
              ),
              const SizedBox(height: 6),
              Text('مقایسه با ${reportPeriodNames[period]} قبل • میانگین ${Jalali.digits(p.perDay.toStringAsFixed(1))} پیام در روز • '
                  '${Jalali.digits(p.people)} مخاطب فعال',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              // ── smart analysis ──
              _InsightsCard(insights: buildInsights(p, period, nameOf: store.displayName, money: _money)),
              const SizedBox(height: 12),
              // ── trend ──
              _Section(
                title: 'روند پیام‌ها',
                icon: Icons.stacked_bar_chart_rounded,
                child: Column(children: [
                  _TrendChart(labels: p.trendLabels, incoming: p.trendIn, outgoing: p.trendOut),
                  const SizedBox(height: 8),
                  Row(children: [
                    _Legend(color: scheme.primary, label: 'دریافتی'),
                    const SizedBox(width: 14),
                    const _Legend(color: Color(0xFFDDC18A), label: 'ارسالی'),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              // ── money per bank in this period ──
              if (p.banks.isNotEmpty) ...[
                _Section(
                  title: 'گردش بانک‌ها در این ${reportPeriodNames[period]}',
                  icon: Icons.account_balance_rounded,
                  child: Column(children: [
                    for (final b in p.banks.take(8))
                      _BankFlowRow(flow: b, peak: p.banks.map((x) => math.max(x.deposits, x.withdrawals)).reduce(math.max), money: _money),
                  ]),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'تراکنش‌ها',
                  icon: Icons.receipt_long_rounded,
                  trailing: TextButton.icon(
                    onPressed: () => _exportCsv(p),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('اکسل'),
                  ),
                  child: Column(children: [
                    for (final e in p.transactions.take(allTransactions ? 200 : 6))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor: (e.kind == FinanceKind.deposit ? _green : scheme.error).withValues(alpha: .12),
                          child: Icon(e.kind == FinanceKind.deposit ? Icons.south_west_rounded : Icons.north_east_rounded,
                              size: 17, color: e.kind == FinanceKind.deposit ? _green : scheme.error),
                        ),
                        title: Text(FinanceLogic.bankOf(e.sender, '')),
                        subtitle: Text(Jalali.short(e.date)),
                        trailing: Text('${e.kind == FinanceKind.deposit ? '+' : '−'} ${_money(e.amountTomans)}',
                            style: TextStyle(fontWeight: FontWeight.w800,
                                color: e.kind == FinanceKind.deposit ? _green : scheme.error)),
                      ),
                    if (p.transactions.length > 6)
                      TextButton(
                        onPressed: () => setState(() => allTransactions = !allTransactions),
                        child: Text(allTransactions ? 'نمایش کمتر' : 'همه ${Jalali.digits(p.transactions.length)} تراکنش'),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              // ── balances ──
              _Section(
                title: 'تازه‌ترین موجودی هر حساب',
                icon: Icons.account_balance_wallet_outlined,
                subtitle: 'از جدیدترین پیامک دارای موجودی هر حساب؛ موجودی تخمینی محاسبه نمی‌شود.',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (data.balances.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('هنوز پیامک بانکی دارای موجودی شناسایی نشده است.', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  for (final bank in banks) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 10, bottom: 7),
                      child: Row(children: [
                        Icon(Icons.account_balance_rounded, color: scheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(bank, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(_money(FinanceLogic.totalBalance(byBank[bank]!)),
                            style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary, fontSize: 12.5)),
                      ]),
                    ),
                    for (final b in byBank[bank]!) _AccountRow(balance: b, money: _money),
                  ],
                ]),
              ),
              if (data.months.any((m) => m.deposits > 0 || m.withdrawals > 0)) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'واریز و برداشت ۶ ماه اخیر',
                  icon: Icons.bar_chart_rounded,
                  child: Column(children: [
                    _MonthChart(months: data.months),
                    const SizedBox(height: 8),
                    Row(children: [
                      const _Legend(color: _green, label: 'واریز'),
                      const SizedBox(width: 14),
                      _Legend(color: scheme.error, label: 'برداشت'),
                    ]),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              // ── categories ──
              _Section(
                title: 'ترکیب پیام‌ها',
                icon: Icons.donut_large_rounded,
                child: Row(children: [
                  SizedBox(width: 120, height: 120, child: CustomPaint(painter: _DonutPainter(p.categories, scheme.surfaceContainerHighest))),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final c in MessageCategory.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            _Legend(color: _catColors[c]!, label: categoryName(c)),
                            const Spacer(),
                            Text(Jalali.digits(p.categories[c] ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(
                              width: 44,
                              child: Text(
                                p.total == 0 ? '' : '${Jalali.digits(((p.categories[c] ?? 0) * 100 / p.total).round())}٪',
                                textAlign: TextAlign.left,
                                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              // ── safety ──
              Row(children: [
                Expanded(child: _MiniStat(icon: Icons.key_rounded, label: 'کد تأیید', value: p.otp, color: const Color(0xFF305F91))),
                const SizedBox(width: 10),
                Expanded(child: _MiniStat(icon: Icons.gpp_maybe_rounded, label: 'پیام مشکوک', value: p.suspicious, color: scheme.error)),
                const SizedBox(width: 10),
                Expanded(child: _MiniStat(icon: Icons.campaign_outlined, label: 'تبلیغاتی',
                    value: p.categories[MessageCategory.advertising] ?? 0, color: const Color(0xFFC0583B))),
              ]),
              if (p.topContacts.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'پرپیام‌ترین مخاطب‌ها',
                  icon: Icons.emoji_events_outlined,
                  child: Column(children: [
                    for (var i = 0; i < p.topContacts.length; i++)
                      _RankRow(
                        index: i,
                        name: store.displayName(p.topContacts[i].key),
                        value: p.topContacts[i].value,
                        peak: p.topContacts.first.value,
                      ),
                  ]),
                ),
              ],
              if (p.topAdvertisers.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'پرتکرارترین فرستنده‌های تبلیغاتی',
                  icon: Icons.campaign_rounded,
                  subtitle: 'برای کم کردن مزاحمت، می‌توانید آن‌ها را مسدود کنید.',
                  child: Column(children: [
                    for (final e in p.topAdvertisers)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.key, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                        subtitle: Text('${Jalali.digits(e.value)} پیام'),
                        trailing: TextButton.icon(
                          onPressed: () => _block(e.key),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('مسدود'),
                        ),
                      ),
                  ]),
                ),
              ],
              if (p.topWords.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'پرتکرارترین کلمه‌ها',
                  icon: Icons.tag_rounded,
                  subtitle: 'از پیام‌های شخصی؛ فقط روی همین گوشی محاسبه می‌شود.',
                  child: _WordCloud(words: p.topWords),
                ),
              ],
              const SizedBox(height: 12),
              _Section(
                title: 'زمان‌های پرپیام',
                icon: Icons.schedule_rounded,
                subtitle: p.total == 0
                    ? null
                    : 'شلوغ‌ترین ساعت: ${Jalali.digits(p.busiestHour)} • شلوغ‌ترین روز: ${weekdayNames[p.busiestWeekday]}',
                child: Column(children: [
                  _HourChart(hours: p.hours),
                  const SizedBox(height: 14),
                  for (var d = 0; d < 7; d++)
                    _Bar(label: weekdayNames[d], value: p.weekdays[d], max: p.weekdays.reduce(math.max)),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'موجودی‌ها از متن آخرین پیامک هر حساب خوانده می‌شوند؛ برای مبلغ قطعی، سامانه رسمی بانک را بررسی کنید. '
              'همه پردازش‌ها فقط روی گوشی انجام می‌شود.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ]),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  const _Section({required this.title, required this.icon, required this.child, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: scheme.primary, size: 21),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            if (trailing != null) trailing!,
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final int? change;
  final Color color;
  final bool upIsBad;
  const _Kpi({required this.label, required this.value, required this.icon, required this.change, required this.color,
      this.upIsBad = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = change;
    final good = c == null ? null : (upIsBad ? c <= 0 : c >= 0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
          ]),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          if (c != null)
            Row(children: [
              Icon(c >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 15,
                  color: good! ? _green : scheme.error),
              const SizedBox(width: 3),
              Text('${Jalali.digits(c.abs())}٪', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: good ? _green : scheme.error)),
            ])
          else
            Text('—', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final List<Insight> insights;
  const _InsightsCard({required this.insights});

  static const _icons = {
    'up': Icons.trending_up_rounded,
    'down': Icons.trending_down_rounded,
    'money': Icons.payments_outlined,
    'balance': Icons.balance_rounded,
    'bank': Icons.account_balance_rounded,
    'shield': Icons.gpp_maybe_rounded,
    'ads': Icons.campaign_outlined,
    'key': Icons.key_rounded,
    'person': Icons.favorite_border_rounded,
    'clock': Icons.schedule_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (insights.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [scheme.tertiaryContainer, scheme.primaryContainer.withValues(alpha: .6)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, color: scheme.tertiary),
          const SizedBox(width: 8),
          Text('تحلیل هوشمند', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        for (final i in insights.take(7))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_icons[i.icon] ?? Icons.lightbulb_outline_rounded, size: 19,
                  color: switch (i.tone) { InsightTone.good => _green, InsightTone.warn => scheme.error, InsightTone.info => scheme.primary }),
              const SizedBox(width: 9),
              Expanded(child: Text(i.text, style: const TextStyle(fontSize: 13.2, height: 1.65))),
            ]),
          ),
      ]),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<String> labels;
  final List<int> incoming;
  final List<int> outgoing;
  const _TrendChart({required this.labels, required this.incoming, required this.outgoing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var peak = 1;
    for (var i = 0; i < incoming.length; i++) {
      peak = math.max(peak, incoming[i] + outgoing[i]);
    }
    final n = incoming.length;
    final every = n > 14 ? (n / 6).ceil() : 1;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 150,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: Tooltip(
                message: '${labels[i]}: ${Jalali.digits(incoming[i])} دریافتی، ${Jalali.digits(outgoing[i])} ارسالی',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: n > 20 ? .8 : 2.5),
                    child: Column(children: [
                      Container(
                        height: 112 * outgoing[i] / peak,
                        decoration: const BoxDecoration(
                            color: Color(0xFFDDC18A), borderRadius: BorderRadius.vertical(top: Radius.circular(3))),
                      ),
                      Container(
                        height: math.max(2, 112 * incoming[i] / peak),
                        decoration: BoxDecoration(color: scheme.primary,
                            borderRadius: outgoing[i] == 0 ? const BorderRadius.vertical(top: Radius.circular(3)) : null),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 16,
                    child: i % every == 0 || i == n - 1
                        ? FittedBox(
                            child: Text(labels[i], style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), maxLines: 1))
                        : null,
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _BankFlowRow extends StatelessWidget {
  final BankFlow flow;
  final int peak;
  final String Function(int) money;
  const _BankFlowRow({required this.flow, required this.peak, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bar(int v, Color c) => ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: peak == 0 ? 0 : v / peak, minHeight: 7, color: c,
              backgroundColor: scheme.surfaceContainerHighest),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(flow.bank, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('${Jalali.digits(flow.count)} تراکنش', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 5),
        Row(children: [
          Expanded(child: bar(flow.deposits, _green)),
          const SizedBox(width: 8),
          SizedBox(width: 118, child: Text('+ ${money(flow.deposits)}', style: const TextStyle(fontSize: 11.5, color: _green))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: bar(flow.withdrawals, scheme.error)),
          const SizedBox(width: 8),
          SizedBox(width: 118, child: Text('− ${money(flow.withdrawals)}', style: TextStyle(fontSize: 11.5, color: scheme.error))),
        ]),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final Map<MessageCategory, int> values;
  final Color empty;
  _DonutPainter(this.values, this.empty);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.values.fold<int>(0, (a, b) => a + b);
    final rect = Offset.zero & size;
    final stroke = size.width * .17;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final arc = rect.deflate(stroke / 2);
    if (total == 0) {
      canvas.drawArc(arc, 0, math.pi * 2, false, paint..color = empty);
      return;
    }
    var start = -math.pi / 2;
    for (final c in MessageCategory.values) {
      final v = values[c] ?? 0;
      if (v == 0) continue;
      final sweep = math.pi * 2 * v / total;
      canvas.drawArc(arc, start, math.max(.001, sweep - .03), false, paint..color = _catColors[c]!);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values;
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  const _MiniStat({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(Jalali.digits(value), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ]),
        ),
      );
}

class _RankRow extends StatelessWidget {
  final int index;
  final String name;
  final int value;
  final int peak;
  const _RankRow({required this.index, required this.name, required this.value, required this.peak});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const medals = ['🥇', '🥈', '🥉'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: index < 3
              ? Text(medals[index], style: const TextStyle(fontSize: 21))
              : CircleAvatar(radius: 12, child: Text(Jalali.digits(index + 1), style: const TextStyle(fontSize: 11.5))),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: peak == 0 ? 0 : value / peak, minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Text('${Jalali.digits(value)} پیام', style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  final String total;
  final int accounts;
  final int banks;
  final DateTime? oldest;
  const _BalanceHero({required this.total, required this.accounts, required this.banks, required this.oldest});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stale = oldest != null && DateTime.now().difference(oldest!).inDays > 30;
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
          Text('${Jalali.digits(accounts)} حساب • ${Jalali.digits(banks)} بانک',
              style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
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
      ]),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final AccountBalance balance;
  final String Function(int) money;
  const _AccountRow({required this.balance, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = DateTime.now().difference(balance.updatedAt).inDays;
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
            Text('به‌روز: ${Jalali.short(balance.updatedAt)}$age',
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
      peak = math.max(peak, math.max(m.deposits, m.withdrawals));
    }
    Widget col(double h, Color c) => AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 10,
          height: h < 2 ? 2 : h,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5)),
        );
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final m in months)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                col(110 * m.deposits / peak, _green),
                const SizedBox(width: 3),
                col(110 * m.withdrawals / peak, scheme.error),
              ]),
              const SizedBox(height: 6),
              Text(m.label, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant), maxLines: 1),
            ]),
          ),
      ]),
    );
  }
}

class _HourChart extends StatelessWidget {
  final List<int> hours;
  const _HourChart({required this.hours});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = hours.reduce(math.max);
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
