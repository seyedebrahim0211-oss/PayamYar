import 'message_logic.dart';

enum FinanceKind { deposit, withdrawal }

class FinanceEntry {
  final FinanceKind kind;
  final int amountTomans;
  final String sender;
  final DateTime date;
  const FinanceEntry(this.kind, this.amountTomans, this.sender, this.date);
}

class FinanceLogic {
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

  static FinanceEntry? parse(MessageRecord m) {
    if (MessageLogic.category(m) != MessageCategory.banking) return null;
    final value = digits(m.body);
    final result = RegExp(r'(واریز|برداشت|خرید|انتقال)\s*(?:مبلغ\s*)?([\d,٬]+)\s*(ریال|تومان)').firstMatch(value);
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
