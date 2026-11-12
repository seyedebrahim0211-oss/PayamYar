import 'message_logic.dart';

enum FinanceKind { deposit, withdrawal }

class FinanceEntry {
  final FinanceKind kind;
  final int amountTomans;
  final String sender;
  final DateTime date;
  const FinanceEntry(this.kind, this.amountTomans, this.sender, this.date);
}

/// Latest balance explicitly stated in a bank SMS; never computed from transfers.
class AccountBalance {
  final String sender;
  final String bank;
  final String? lastFour;
  final int amountTomans;
  final DateTime updatedAt;
  const AccountBalance(this.sender, this.lastFour, this.amountTomans, this.updatedAt,
      {String? bank}) : bank = bank ?? sender;
  String get label => lastFour == null ? 'حساب نامشخص' : 'حساب / کارت ••••$lastFour';
}

class FinanceLogic {
  static const bankNames = <String>[
    'ملی', 'ملت', 'صادرات', 'تجارت', 'سپه', 'کشاورزی',
    'مسکن', 'رفاه', 'پاسارگاد', 'پارسیان', 'سامان', 'اقتصاد نوین',
    'آینده', 'شهر', 'دی', 'سینا', 'گردشگری', 'ایران زمین',
    'سرمایه', 'خاورمیانه', 'کارآفرین', 'توسعه تعاون', 'پست بانک',
    'رسالت', 'مهر ایران', 'قرض الحسنه مهر', 'انصار', 'قوامین',
  ];

  /// Use sender/provider evidence, never infer a financial account from message totals.
  static String bankOf(String sender, String body) {
    final source = ('$sender $body').replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک').replaceAll('\u200c', ' ');
    for (final bank in bankNames) {
      if (source.contains('بانک $bank') || source.contains('بانك $bank') ||
          sender.trim() == bank || sender.startsWith('$bank ')) {
        return 'بانک $bank';
      }
    }
    return sender.trim().isEmpty ? 'بانک نامشخص' : sender.trim();
  }

  static String digits(String s) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    return s.split('').map((c) {
      final p = persian.indexOf(c);
      if (p >= 0) return p.toString();
      final a = arabic.indexOf(c);
      if (a >= 0) return a.toString();
      return c;
    }).join();
  }

  static final _transaction = RegExp(r'(واریز|برداشت|خرید|انتقال)\s*(?:مبلغ\s*)?([\d,٬]+)\s*(ریال|تومان)');

  static FinanceEntry? parse(MessageRecord m) {
    if (MessageLogic.category(m) != MessageCategory.banking) return null;
    final value = digits(m.body);
    final result = _transaction.firstMatch(value);
    if (result == null) return null;
    final number = int.tryParse(result.group(2)!.replaceAll(RegExp(r'[,٬]'), ''));
    if (number == null || number <= 0) return null;
    final toman = result.group(3) == 'ریال' ? number ~/ 10 : number;
    if (toman <= 0) return null;
    final kind = result.group(1) == 'واریز' ? FinanceKind.deposit : FinanceKind.withdrawal;
    return FinanceEntry(kind, toman, m.sender, m.date);
  }

  static List<FinanceEntry> extract(Iterable<MessageRecord> messages) =>
      messages.map(parse).whereType<FinanceEntry>().toList();

  static int total(Iterable<FinanceEntry> entries, FinanceKind kind) =>
      entries.where((e) => e.kind == kind).fold(0, (sum, e) => sum + e.amountTomans);

  /// Only returns explicit balance values with a currency unit.
  /// Different account suffixes remain separate, and unknown accounts are not summed.
  static List<AccountBalance> latestBalances(Iterable<MessageRecord> messages) {
    final latest = <String, AccountBalance>{};
    final balance = RegExp(
      r'(?:موجودی|موجودي|مانده(?:\s+(?:حساب|کارت|سپرده))?|باقی\s*مانده)'
      r'(?:\s+فعلی)?\s*[:：\-]?\s*(?:مبلغ\s*)?'
      r'([\d,٬،\s]+)\s*(ریال|تومان)',
      caseSensitive: false);
    final account = RegExp(
      r'(?:شماره\s*)?(?:حساب|کارت|سپرده|شبا)\s*[:：#\-]?\s*'
      r'([*xX×\-\s\d]{4,40})',
      caseSensitive: false);
    for (final m in messages) {
      if (m.outgoing || MessageLogic.category(m) != MessageCategory.banking) continue;
      final raw = digits(m.body).replaceAll('ي', 'ی').replaceAll('ك', 'ک')
          .replaceAll('\u200c', ' ');
      final match = balance.firstMatch(raw);
      if (match == null) continue;
      final number = int.tryParse(match.group(1)!.replaceAll(RegExp(r'[,\s٬،]'), ''));
      if (number == null || number < 0) continue;
      final value = match.group(2) == 'ریال' ? number ~/ 10 : number;
      // The amount itself must never be read as an account number ("مانده حساب: 1500000 ریال"),
      // otherwise every new balance became a separate fake account and old values stayed visible.
      final withoutAmount = raw.replaceRange(match.start, match.end, ' ');
      final idMatch = account.firstMatch(withoutAmount);
      final suffix = idMatch?.group(1)?.replaceAll(RegExp(r'[^0-9]'), '');
      final lastFour = suffix != null && suffix.length >= 4
          ? suffix.substring(suffix.length - 4) : null;
      // One account per bank + last four digits, even when the bank texts from several senders.
      final bank = bankOf(m.sender, m.body);
      final key = '$bank|${lastFour ?? 'unknown'}';
      if (!latest.containsKey(key) || m.date.isAfter(latest[key]!.updatedAt)) {
        latest[key] = AccountBalance(m.sender, lastFour, value, m.date, bank: bank);
      }
    }
    // An "unknown account" balance older than a known account of the same bank is stale noise.
    final newestKnown = <String, DateTime>{};
    for (final b in latest.values.where((b) => b.lastFour != null)) {
      final seen = newestKnown[b.bank];
      if (seen == null || b.updatedAt.isAfter(seen)) newestKnown[b.bank] = b.updatedAt;
    }
    latest.removeWhere((_, b) => b.lastFour == null && newestKnown[b.bank] != null &&
        !b.updatedAt.isAfter(newestKnown[b.bank]!));
    return latest.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Sum of the latest stated balance of every account.
  static int totalBalance(Iterable<AccountBalance> balances) =>
      balances.fold(0, (sum, b) => sum + b.amountTomans);

  static String formatTomans(int amount) {
    final digits = amount.abs().toString();
    final parts = <String>[];
    for (var i = digits.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      parts.insert(0, digits.substring(start, i));
    }
    return '${amount < 0 ? '-' : ''}${parts.join(',')} تومان';
  }
}
