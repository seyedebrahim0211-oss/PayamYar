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

/// "Top" statistics for one time window (week, month or year).
class PeriodInsight {
  final int received;
  final int sent;
  /// Conversation key → message count, personal contacts only, most active first.
  final List<MapEntry<String, int>> topContacts;
  final List<MapEntry<String, int>> topWords;
  /// Messages per hour of day (24 entries).
  final List<int> hours;
  /// Messages per weekday, index 0 = شنبه … 6 = جمعه.
  final List<int> weekdays;
  final Map<MessageCategory, int> categories;
  const PeriodInsight(this.received, this.sent, this.topContacts, this.topWords, this.hours, this.weekdays,
      this.categories);

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

enum ReportPeriod { week, month, year }

const reportPeriodNames = {ReportPeriod.week: 'هفته', ReportPeriod.month: 'ماه', ReportPeriod.year: 'سال'};
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
  const ReportResult({required this.deposits, required this.withdrawals, required this.recent,
      required this.biggest, required this.balances, required this.months, required this.counts,
      required this.periods, required this.total});

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
ReportResult buildReport(List<MessageRecord> messages) {
  final now = DateTime.now();
  final since30 = now.subtract(const Duration(days: 30));
  final counts = <MessageCategory, int>{for (final c in MessageCategory.values) c: 0};
  final recent = <FinanceEntry>[];
  final allEntries = <FinanceEntry>[];
  final starts = {
    ReportPeriod.week: now.subtract(const Duration(days: 7)),
    ReportPeriod.month: now.subtract(const Duration(days: 30)),
    ReportPeriod.year: now.subtract(const Duration(days: 365)),
  };
  final received = {for (final p in ReportPeriod.values) p: 0};
  final sent = {for (final p in ReportPeriod.values) p: 0};
  final contacts = {for (final p in ReportPeriod.values) p: <String, int>{}};
  final words = {for (final p in ReportPeriod.values) p: <String, int>{}};
  final hours = {for (final p in ReportPeriod.values) p: List<int>.filled(24, 0)};
  final weekdays = {for (final p in ReportPeriod.values) p: List<int>.filled(7, 0)};
  final cats = {for (final p in ReportPeriod.values) p: <MessageCategory, int>{for (final c in MessageCategory.values) c: 0}};
  final yearStart = starts[ReportPeriod.year]!;

  for (final m in messages) {
    final category = MessageLogic.category(m);
    counts[category] = counts[category]! + 1;
    if (category == MessageCategory.banking && !m.outgoing) {
      final entry = FinanceLogic.parse(m);
      if (entry != null) {
        if (m.date.isAfter(yearStart)) allEntries.add(entry);
        if (m.date.isAfter(since30)) recent.add(entry);
      }
    }
    if (!m.date.isAfter(yearStart)) continue;
    final key = ConversationLogic.normalize(m.sender);
    // Dart weekday: Monday = 1 … Sunday = 7; shift so that Saturday = 0.
    final weekday = (m.date.weekday + 1) % 7;
    List<String>? tokens;
    for (final p in ReportPeriod.values) {
      if (!m.date.isAfter(starts[p]!)) continue;
      if (m.outgoing) {
        sent[p] = sent[p]! + 1;
      } else {
        received[p] = received[p]! + 1;
      }
      cats[p]![category] = cats[p]![category]! + 1;
      hours[p]![m.date.hour]++;
      weekdays[p]![weekday]++;
      if (category == MessageCategory.personal) {
        contacts[p]![key] = (contacts[p]![key] ?? 0) + 1;
        tokens ??= m.body
            .replaceAll('ي', 'ی')
            .replaceAll('ك', 'ک')
            .split(_wordSplit)
            .map((w) => w.replaceAll('‌', '').trim())
            .where((w) => w.length >= 3 && !_stopWords.contains(w))
            .toList();
        final bag = words[p]!;
        for (final w in tokens) {
          bag[w] = (bag[w] ?? 0) + 1;
        }
      }
    }
  }

  List<MapEntry<String, int>> top(Map<String, int> map, int n) {
    final list = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  final periods = <ReportPeriod, PeriodInsight>{
    for (final p in ReportPeriod.values)
      p: PeriodInsight(received[p]!, sent[p]!, top(contacts[p]!, 5),
          top(words[p]!..removeWhere((_, v) => v < 2), 12), hours[p]!, weekdays[p]!, cats[p]!),
  };

  // Six Jalali months, oldest first.
  final monthly = <int, List<int>>{};
  for (final e in allEntries) {
    final j = Jalali.fromGregorian(e.date.year, e.date.month, e.date.day);
    final k = j[0] * 12 + (j[1] - 1);
    final slot = monthly[k] ??= [0, 0];
    if (e.kind == FinanceKind.deposit) {
      slot[0] += e.amountTomans;
    } else {
      slot[1] += e.amountTomans;
    }
  }
  final jn = Jalali.fromGregorian(now.year, now.month, now.day);
  final current = jn[0] * 12 + (jn[1] - 1);
  final months = <MonthFlow>[
    for (var k = current - 5; k <= current; k++)
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
  );
}
