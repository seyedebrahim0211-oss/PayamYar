enum MessageCategory { personal, banking, service, advertising }
class MessageRecord {
  final int? id;
  final bool read;
  final int type;
  final int delivery;
  final String sender;
  final String body;
  final DateTime date;
  final bool outgoing;
  const MessageRecord({required this.sender, required this.body, required this.date, this.outgoing = false, this.id, this.read = true, this.type = 1, this.delivery = -1});
}
class MessageLogic {
  // Compiled once: category() runs for every message on each inbox rebuild.
  static final _banking = RegExp(r'بانک|واریز|برداشت|موجودی|تراکنش|atm|card|bank');
  static final _advertising = RegExp(r'تبلیغ|تخفیف|فروش ویژه|حراج|لغو\s*11');
  static final _service = RegExp(r'رمز پویا|کد تایید|کد تأیید|بسته اینترنت|قبض|مرسوله');
  static final _scam = RegExp(r'برنده شدید|ابلاغیه قضایی|حساب شما مسدود|پرداخت فوری|جایزه نقدی');
  static final _link = RegExp(r'https?://|www\.|\.ir|\.com');

  static MessageCategory category(MessageRecord m) {
    final s = ('${m.sender} ${m.body}').toLowerCase();
    if (_banking.hasMatch(s)) return MessageCategory.banking;
    if (_advertising.hasMatch(s)) return MessageCategory.advertising;
    if (_service.hasMatch(s)) return MessageCategory.service;
    return MessageCategory.personal;
  }
  static bool suspicious(String body) {
    final s = body.toLowerCase();
    return _scam.hasMatch(s) && _link.hasMatch(s);
  }
  static List<MessageRecord> search(List<MessageRecord> source, String term, {DateTime? from, DateTime? to}) =>
    source.where((m) => (term.isEmpty || ('${m.sender} ${m.body}').toLowerCase().contains(term.toLowerCase())) &&
      (from == null || !m.date.isBefore(from)) && (to == null || !m.date.isAfter(to))).toList();

  static String _latinDigits(String s) {
    const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
    return s.split('').map((c) {
      final p = fa.indexOf(c);
      if (p >= 0) return '$p';
      final a = ar.indexOf(c);
      return a >= 0 ? '$a' : c;
    }).join();
  }

  /// One-time password / verification code in the message, for a one-tap copy button.
  static String? otp(String body) {
    final s = _latinDigits(body);
    final match = RegExp(
      r'(?:کد|رمز|code|otp|password|pin)[^\d\n]{0,25}(\d{4,8})(?!\d)', caseSensitive: false).firstMatch(s);
    return match?.group(1);
  }
}
