import 'conversation_logic.dart';
import 'finance_logic.dart';
import 'jalali.dart';
import 'message_logic.dart';

/// Deposits and withdrawals of one Jalali month.
class MonthFlow {
  final String label;
  final int deposits;
  final int withdrawals;
  const MonthFlow(this.label, this.deposits, this.withdrawals);
}

/// Money in/out of one bank inside a period.
class BankFlow {
  final String bank;
  final int deposits;
  final int withdrawals;
  final int count;
  const BankFlow(this.bank, this.deposits, this.withdrawals, this.count);
  int get net => deposits - withdrawals;
}

/// Tone of an automatic insight card.
enum InsightTone { good, warn, info }

/// One line of the "smart analysis" card, built on the phone from the numbers below.
class Insight {
  final String text;
  final InsightTone tone;
  final String icon; // key mapped to an icon by the UI
  const Insight(this.text, this.tone, this.icon);
}

/// Statistics for one time window (week, month, quarter or year) and the window before it.
class PeriodInsight {
  final int received;
  final int sent;
  final int prevReceived;
  final int prevSent;
  /// Conversation key → message count, personal contacts only, most active first.
  final List<MapEntry<String, int>> topContacts;
  final List<MapEntry<String, int>> topWords;
  /// Advertising senders with the most messages (candidates to block).
  final List<MapEntry<String, int>> topAdvertisers;
  /// Messages per hour of day (24 entries).
  final List<int> hours;
  /// Messages per weekday, index 0 = شنبه … 6 = جمعه.
  final List<int> weekdays;
  final Map<MessageCategory, int> categories;
  // ── trend: oldest bucket first ──
  final List<String> trendLabels;
  final List<int> trendIn;
  final List<int> trendOut;
  // ── money ──
  final int deposits;
  final int withdrawals;
  final int prevDeposits;
  final int prevWithdrawals;
  final List<BankFlow> banks;
  final List<FinanceEntry> transactions;
  // ── safety & service ──
  final int otp;
  final int suspicious;
  final int people;
  final int days;

  const PeriodInsight({
    required this.received,
    required this.sent,
    this.prevReceived = 0,
    this.prevSent = 0,
    this.topContacts = const [],
    this.topWords = const [],
    this.topAdvertisers = const [],
    required this.hours,
    required this.weekdays,
    required this.categories,
    this.trendLabels = const [],
    this.trendIn = const [],
    this.trendOut = const [],
    this.deposits = 0,
    this.withdrawals = 0,
    this.prevDeposits = 0,
    this.prevWithdrawals = 0,
    this.banks = const [],
    this.transactions = const [],
    this.otp = 0,
    this.suspicious = 0,
    this.people = 0,
    this.days = 30,
  });

  int get total => received + sent;
  int get prevTotal => prevReceived + prevSent;
  int get net => deposits - withdrawals;
  double get perDay => days == 0 ? 0 : total / days;

  int get busiestHour {
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (hours[h] > hours[best]) best = h;
    }
    return best;
  }

  int get busiestWeekday {
    var best = 0;
    for (var d = 1; d < 7; d++) {
      if (weekdays[d] > weekdays[best]) best = d;
    }
    return best;
  }
}

enum ReportPeriod { week, month, quarter, year }

const reportPeriodNames = {
  ReportPeriod.week: 'هفته',
  ReportPeriod.month: 'ماه',
  ReportPeriod.quarter: '۳ ماه',
  ReportPeriod.year: 'سال',
};
const reportPeriodDays = {ReportPeriod.week: 7, ReportPeriod.month: 30, ReportPeriod.quarter: 91, ReportPeriod.year: 365};
const weekdayNames = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];

/// Everything the reports screen shows. Built off the UI thread by [buildReport].
class ReportResult {
  final int deposits;
  final int withdrawals;
  final List<FinanceEntry> recent;
  final List<FinanceEntry> biggest;
  final List<AccountBalance> balances;
  final List<MonthFlow> months;
  final Map<MessageCategory, int> counts;
  final Map<ReportPeriod, PeriodInsight> periods;
  final int total;
  final DateTime? builtAt;
  const ReportResult({required this.deposits, required this.withdrawals, required this.recent,
      required this.biggest, required this.balances, required this.months, required this.counts,
      required this.periods, required this.total, this.builtAt});

  static final empty = ReportResult(deposits: 0, withdrawals: 0, recent: const [], biggest: const [],
      balances: const [], months: const [], counts: {for (final c in MessageCategory.values) c: 0},
      periods: const {}, total: 0);

  int get totalBalance => FinanceLogic.totalBalance(balances);
}

/// Common Persian filler words that say nothing about what people talk about.
const _stopWords = {
  'که', 'از', 'به', 'در', 'با', 'را', 'این', 'آن', 'برای', 'تا', 'هم', 'یا', 'و', 'اگر', 'ولی', 'اما', 'من', 'تو',
  'شما', 'ما', 'او', 'است', 'هست', 'بود', 'شد', 'شده', 'می', 'نمی', 'یه', 'یک', 'رو', 'دیگه', 'دیگر', 'چی', 'چه',
  'کن', 'کنید', 'کنم', 'باشه', 'باشد', 'هستم', 'هستی', 'داره', 'دارد', 'دارم', 'نه', 'آره', 'بله', 'سلام', 'خب',
  'خوب', 'مرسی', 'ممنون', 'اون', 'اینو', 'اونو', 'کجا', 'کی', 'چرا', 'وقتی', 'همه', 'خیلی', 'فقط', 'الان', 'بعد',
  'قبل', 'روی', 'زیر', 'پیش', 'بر', 'های', 'ها', 'ای', 'ام', 'ات', 'اش', 'تون', 'مون', 'شون', 'نیست', 'هستند',
  'لغو', 'ارسال', 'عدد', 'جهت', 'کد', 'سایت', 'لینک', 'ریال', 'تومان',
};

final _wordSplit = RegExp(r'[^؀-ۿa-zA-Z‌]+');

/// Runs in a background isolate (see AppStore._runReport); must stay free of Flutter APIs.
ReportResult buildReport(List<MessageRecord> messages) => buildReportAt(messages, DateTime.now());

class _Acc {
  final int days;
  final DateTime start;
  final DateTime prevStart;
  int received = 0, sent = 0, prevReceived = 0, prevSent = 0;
  int deposits = 0, withdrawals = 0, prevDeposits = 0, prevWithdrawals = 0;
  int otp = 0, suspicious = 0;
  final contacts = <String, int>{};
  final words = <String, int>{};
  final ads = <String, int>{};
  final hours = List<int>.filled(24, 0);
  final weekdays = List<int>.filled(7, 0);
  final cats = <MessageCategory, int>{for (final c in MessageCategory.values) c: 0};
  final banks = <String, List<int>>{};
  final tx = <FinanceEntry>[];
  late final List<int> trendIn;
  late final List<int> trendOut;
  late final List<String> trendLabels;
  _Acc(this.days, DateTime now)
      : start = now.subtract(Duration(days: days)),
        prevStart = now.subtract(Duration(days: days * 2));
}

ReportResult buildReportAt(List<MessageRecord> messages, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final since30 = now.subtract(const Duration(days: 30));
  final counts = <MessageCategory, int>{for (final c in MessageCategory.values) c: 0};
  final recent = <FinanceEntry>[];
  final yearEntries = <FinanceEntry>[];
  final acc = {for (final p in ReportPeriod.values) p: _Acc(reportPeriodDays[p]!, now)};

  // Trend buckets: week/month = days, quarter = 13 weeks, year = 12 Jalali months.
  final jNow = Jalali.fromGregorian(now.year, now.month, now.day);
  final currentMonthKey = jNow[0] * 12 + (jNow[1] - 1);
  for (final p in ReportPeriod.values) {
    final a = acc[p]!;
    final n = switch (p) { ReportPeriod.week => 7, ReportPeriod.month => 30, ReportPeriod.quarter => 13, ReportPeriod.year => 12 };
    a.trendIn = List<int>.filled(n, 0);
    a.trendOut = List<int>.filled(n, 0);
    a.trendLabels = List<String>.generate(n, (i) {
      final back = n - 1 - i;
      switch (p) {
        case ReportPeriod.week:
          final d = today.subtract(Duration(days: back));
          return weekdayNames[(d.weekday + 1) % 7].substring(0, 1);
        case ReportPeriod.month:
          final d = today.subtract(Duration(days: back));
          final j = Jalali.fromGregorian(d.year, d.month, d.day);
          return Jalali.digits(j[2]);
        case ReportPeriod.quarter:
          return Jalali.digits(i + 1);
        case ReportPeriod.year:
          return Jalali.months[(currentMonthKey - back) % 12];
      }
    });
  }

  int? bucket(ReportPeriod p, DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final back = today.difference(day).inDays;
    switch (p) {
      case ReportPeriod.week:
        return back >= 0 && back < 7 ? 6 - back : null;
      case ReportPeriod.month:
        return back >= 0 && back < 30 ? 29 - back : null;
      case ReportPeriod.quarter:
        final w = back ~/ 7;
        return back >= 0 && w < 13 ? 12 - w : null;
      case ReportPeriod.year:
        final j = Jalali.fromGregorian(d.year, d.month, d.day);
        final k = currentMonthKey - (j[0] * 12 + (j[1] - 1));
        return k >= 0 && k < 12 ? 11 - k : null;
    }
  }

  final twoYears = now.subtract(const Duration(days: 730));
  for (final m in messages) {
    final category = MessageLogic.category(m);
    counts[category] = counts[category]! + 1;
    if (!m.date.isAfter(twoYears)) continue;
    FinanceEntry? entry;
    if (category == MessageCategory.banking && !m.outgoing) {
      entry = FinanceLogic.parse(m);
      if (entry != null) {
        if (m.date.isAfter(now.subtract(const Duration(days: 365)))) yearEntries.add(entry);
        if (m.date.isAfter(since30)) recent.add(entry);
      }
    }
    final key = ConversationLogic.normalize(m.sender);
    final weekday = (m.date.weekday + 1) % 7; // Saturday = 0
    final isOtp = !m.outgoing && MessageLogic.otp(m.body) != null;
    final isScam = !m.outgoing && MessageLogic.suspicious(m.body);
    List<String>? tokens;
    for (final p in ReportPeriod.values) {
      final a = acc[p]!;
      if (!m.date.isAfter(a.prevStart)) continue;
      if (!m.date.isAfter(a.start)) {
        // The window before: only totals, for the "compared with the previous period" arrows.
        if (m.outgoing) {
          a.prevSent++;
        } else {
          a.prevReceived++;
        }
        if (entry != null) {
          if (entry.kind == FinanceKind.deposit) {
            a.prevDeposits += entry.amountTomans;
          } else {
            a.prevWithdrawals += entry.amountTomans;
          }
        }
        continue;
      }
      if (m.outgoing) {
        a.sent++;
      } else {
        a.received++;
      }
      a.cats[category] = a.cats[category]! + 1;
      a.hours[m.date.hour]++;
      a.weekdays[weekday]++;
      if (isOtp) a.otp++;
      if (isScam) a.suspicious++;
      final b = bucket(p, m.date);
      if (b != null) {
        if (m.outgoing) {
          a.trendOut[b]++;
        } else {
          a.trendIn[b]++;
        }
      }
      if (entry != null) {
        final bank = FinanceLogic.bankOf(m.sender, m.body);
        final slot = a.banks[bank] ??= [0, 0, 0];
        if (entry.kind == FinanceKind.deposit) {
          a.deposits += entry.amountTomans;
          slot[0] += entry.amountTomans;
        } else {
          a.withdrawals += entry.amountTomans;
          slot[1] += entry.amountTomans;
        }
        slot[2]++;
        a.tx.add(entry);
      }
      if (category == MessageCategory.advertising && !m.outgoing) {
        a.ads[m.sender] = (a.ads[m.sender] ?? 0) + 1;
      }
      if (category == MessageCategory.personal) {
        a.contacts[key] = (a.contacts[key] ?? 0) + 1;
        tokens ??= m.body
            .replaceAll('ي', 'ی')
            .replaceAll('ك', 'ک')
            .split(_wordSplit)
            .map((w) => w.replaceAll('‌', '').trim())
            .where((w) => w.length >= 3 && !_stopWords.contains(w))
            .toList();
        for (final w in tokens) {
          a.words[w] = (a.words[w] ?? 0) + 1;
        }
      }
    }
  }

  List<MapEntry<String, int>> top(Map<String, int> map, int n, {int min = 1}) {
    final list = map.entries.where((e) => e.value >= min).toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  final periods = <ReportPeriod, PeriodInsight>{
    for (final p in ReportPeriod.values)
      p: () {
        final a = acc[p]!;
        final banks = [for (final e in a.banks.entries) BankFlow(e.key, e.value[0], e.value[1], e.value[2])]
          ..sort((x, y) => (y.deposits + y.withdrawals).compareTo(x.deposits + x.withdrawals));
        a.tx.sort((x, y) => y.date.compareTo(x.date));
        return PeriodInsight(
          received: a.received,
          sent: a.sent,
          prevReceived: a.prevReceived,
          prevSent: a.prevSent,
          topContacts: top(a.contacts, 8),
          topWords: top(a.words, 14, min: 2),
          topAdvertisers: top(a.ads, 5, min: 2),
          hours: a.hours,
          weekdays: a.weekdays,
          categories: a.cats,
          trendLabels: a.trendLabels,
          trendIn: a.trendIn,
          trendOut: a.trendOut,
          deposits: a.deposits,
          withdrawals: a.withdrawals,
          prevDeposits: a.prevDeposits,
          prevWithdrawals: a.prevWithdrawals,
          banks: banks,
          transactions: a.tx,
          otp: a.otp,
          suspicious: a.suspicious,
          people: a.contacts.length,
          days: a.days,
        );
      }(),
  };

  // Six Jalali months, oldest first.
  final monthly = <int, List<int>>{};
  for (final e in yearEntries) {
    final j = Jalali.fromGregorian(e.date.year, e.date.month, e.date.day);
    final k = j[0] * 12 + (j[1] - 1);
    final slot = monthly[k] ??= [0, 0];
    if (e.kind == FinanceKind.deposit) {
      slot[0] += e.amountTomans;
    } else {
      slot[1] += e.amountTomans;
    }
  }
  final months = <MonthFlow>[
    for (var k = currentMonthKey - 5; k <= currentMonthKey; k++)
      MonthFlow(Jalali.months[k % 12], monthly[k]?[0] ?? 0, monthly[k]?[1] ?? 0),
  ];

  final biggest = recent.where((e) => e.kind == FinanceKind.withdrawal).toList()
    ..sort((a, b) => b.amountTomans.compareTo(a.amountTomans));

  return ReportResult(
    deposits: FinanceLogic.total(recent, FinanceKind.deposit),
    withdrawals: FinanceLogic.total(recent, FinanceKind.withdrawal),
    recent: recent,
    biggest: biggest.take(5).toList(),
    balances: FinanceLogic.latestBalances(messages),
    months: months,
    counts: counts,
    periods: periods,
    total: messages.length,
    builtAt: now,
  );
}

/// Percent change from [before] to [now]; null when there is nothing to compare.
int? percentChange(int now, int before) {
  if (before <= 0) return null;
  return ((now - before) * 100 / before).round();
}

/// Plain-language findings for the selected period, most useful first.
List<Insight> buildInsights(PeriodInsight p, ReportPeriod period, {String Function(String key)? nameOf,
    String Function(int tomans)? money}) {
  final out = <Insight>[];
  final label = reportPeriodNames[period]!;
  String fa(Object v) => Jalali.digits(v);
  final m = money ?? (int v) => fa(FinanceLogic.formatTomans(v));

  final change = percentChange(p.total, p.prevTotal);
  if (change != null && change.abs() >= 10) {
    out.add(Insight(
      change > 0
          ? 'حجم پیام‌ها در این $label ${fa(change)}٪ بیشتر از $label قبل بوده است.'
          : 'حجم پیام‌ها در این $label ${fa(-change)}٪ کمتر از $label قبل بوده است.',
      InsightTone.info,
      change > 0 ? 'up' : 'down',
    ));
  }
  final spend = percentChange(p.withdrawals, p.prevWithdrawals);
  if (spend != null && spend.abs() >= 15 && p.withdrawals > 0) {
    out.add(Insight(
      spend > 0
          ? 'برداشت‌های بانکی ${fa(spend)}٪ افزایش داشته است (${m(p.withdrawals)}).'
          : 'برداشت‌های بانکی ${fa(-spend)}٪ کاهش یافته است؛ آفرین! (${m(p.withdrawals)})',
      spend > 0 ? InsightTone.warn : InsightTone.good,
      'money',
    ));
  }
  if (p.deposits > 0 || p.withdrawals > 0) {
    out.add(Insight(
      p.net >= 0
          ? 'جمع واریز از برداشت بیشتر بوده؛ خالص ${m(p.net)} به حساب‌ها اضافه شده.'
          : 'برداشت از واریز بیشتر بوده؛ خالص ${m(-p.net)} از حساب‌ها کم شده.',
      p.net >= 0 ? InsightTone.good : InsightTone.warn,
      'balance',
    ));
  }
  if (p.banks.isNotEmpty && p.banks.first.withdrawals > 0) {
    final top = [...p.banks]..sort((a, b) => b.withdrawals.compareTo(a.withdrawals));
    out.add(Insight('بیشترین برداشت از ${top.first.bank}: ${m(top.first.withdrawals)}.', InsightTone.info, 'bank'));
  }
  if (p.suspicious > 0) {
    out.add(Insight('${fa(p.suspicious)} پیام مشکوک به کلاهبرداری (لینک + وعده جایزه/ابلاغیه) دریافت شده؛ روی لینک‌ها نزنید.',
        InsightTone.warn, 'shield'));
  }
  final ads = p.categories[MessageCategory.advertising] ?? 0;
  if (p.received > 0 && ads * 100 / p.received >= 25) {
    final share = (ads * 100 / p.received).round();
    final who = p.topAdvertisers.isEmpty ? '' : ' پرتکرارترین: ${p.topAdvertisers.first.key}.';
    out.add(Insight('${fa(share)}٪ پیام‌های دریافتی تبلیغاتی بوده‌اند.$who', InsightTone.warn, 'ads'));
  }
  if (p.otp > 0) {
    out.add(Insight('${fa(p.otp)} کد تأیید دریافت شده؛ کدها را با هیچ‌کس به اشتراک نگذارید.', InsightTone.info, 'key'));
  }
  if (p.topContacts.isNotEmpty) {
    final who = nameOf?.call(p.topContacts.first.key) ?? p.topContacts.first.key;
    out.add(Insight('بیشترین گفتگو با $who (${fa(p.topContacts.first.value)} پیام).', InsightTone.good, 'person'));
  }
  if (p.total > 0) {
    final h = p.busiestHour;
    out.add(Insight('اوج پیام‌ها ساعت ${fa(h)} تا ${fa((h + 1) % 24)} و روز ${weekdayNames[p.busiestWeekday]} است.',
        InsightTone.info, 'clock'));
  }
  return out;
}

/// Plain-text report for sharing (messenger, e-mail, notes).
String reportAsText(ReportResult r, PeriodInsight p, ReportPeriod period, {required String Function(String key) nameOf,
    required String Function(int tomans) money}) {
  final b = StringBuffer();
  String fa(Object v) => Jalali.digits(v);
  final now = r.builtAt ?? DateTime.now();
  final j = Jalali.fromGregorian(now.year, now.month, now.day);
  b.writeln('📊 گزارش پیامیار — ${reportPeriodNames[period]} اخیر (${fa('${j[0]}/${j[1]}/${j[2]}')})');
  b.writeln('');
  b.writeln('✉️ دریافتی: ${fa(p.received)} • ارسالی: ${fa(p.sent)} • میانگین روزانه: ${fa(p.perDay.toStringAsFixed(1))}');
  for (final c in MessageCategory.values) {
    final names = {
      MessageCategory.personal: 'شخصی',
      MessageCategory.banking: 'بانکی',
      MessageCategory.service: 'خدماتی',
      MessageCategory.advertising: 'تبلیغاتی',
    };
    b.writeln('   • ${names[c]}: ${fa(p.categories[c] ?? 0)}');
  }
  b.writeln('');
  b.writeln('💰 واریز: ${money(p.deposits)} • برداشت: ${money(p.withdrawals)} • خالص: ${money(p.net)}');
  for (final bank in p.banks.take(6)) {
    b.writeln('   • ${bank.bank}: +${money(bank.deposits)} / -${money(bank.withdrawals)}');
  }
  if (r.balances.isNotEmpty) b.writeln('🏦 جمع آخرین موجودی‌ها: ${money(r.totalBalance)}');
  if (p.topContacts.isNotEmpty) {
    b.writeln('');
    b.writeln('👥 پرپیام‌ترین‌ها:');
    for (final e in p.topContacts.take(5)) {
      b.writeln('   • ${nameOf(e.key)}: ${fa(e.value)}');
    }
  }
  final ins = buildInsights(p, period, nameOf: nameOf, money: money);
  if (ins.isNotEmpty) {
    b.writeln('');
    b.writeln('💡 تحلیل هوشمند:');
    for (final i in ins.take(6)) {
      b.writeln('   • ${i.text}');
    }
  }
  b.writeln('');
  b.writeln('— محاسبه‌شده روی گوشی با پیامیار');
  return b.toString();
}

/// Transactions of a period as CSV rows (date, bank, type, amount in tomans).
List<List<String>> transactionsAsRows(List<FinanceEntry> entries) => [
      ['تاریخ', 'ساعت', 'بانک', 'نوع', 'مبلغ (تومان)'],
      for (final e in entries)
        () {
          final j = Jalali.fromGregorian(e.date.year, e.date.month, e.date.day);
          return [
            '${j[0]}/${j[1].toString().padLeft(2, '0')}/${j[2].toString().padLeft(2, '0')}',
            '${e.date.hour.toString().padLeft(2, '0')}:${e.date.minute.toString().padLeft(2, '0')}',
            FinanceLogic.bankOf(e.sender, ''),
            e.kind == FinanceKind.deposit ? 'واریز' : 'برداشت',
            '${e.amountTomans}',
          ];
        }(),
    ];
