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
  static MessageCategory category(MessageRecord m) {
    final s = ('${m.sender} ${m.body}').toLowerCase();
    if (RegExp(r'بانک|واریز|برداشت|موجودی|تراکنش|atm|card|bank').hasMatch(s)) return MessageCategory.banking;
    if (RegExp(r'تبلیغ|تخفیف|فروش ویژه|حراج|لغو\s*11').hasMatch(s)) return MessageCategory.advertising;
    if (RegExp(r'رمز پویا|کد تایید|کد تأیید|بسته اینترنت|قبض|مرسوله').hasMatch(s)) return MessageCategory.service;
    return MessageCategory.personal;
  }
  static bool suspicious(String body) {
    final s = body.toLowerCase();
    return RegExp(r'برنده شدید|ابلاغیه قضایی|حساب شما مسدود|پرداخت فوری|جایزه نقدی').hasMatch(s) &&
      RegExp(r'https?://|www\.|\.ir|\.com').hasMatch(s);
  }
  static List<MessageRecord> search(List<MessageRecord> source, String term, {DateTime? from, DateTime? to}) =>
    source.where((m) => (term.isEmpty || ('${m.sender} ${m.body}').toLowerCase().contains(term.toLowerCase())) &&
      (from == null || !m.date.isBefore(from)) && (to == null || !m.date.isAfter(to))).toList();
}

