import '../jalali.dart';
import '../message_logic.dart';

class MessageActions {
  static String _digits(String text) => text.replaceAllMapped(RegExp('[۰-۹٠-٩]'),
      (m) => ((m[0]!.codeUnitAt(0) - 0x660) % 16).toString());

  static ({String code, Uri site})? shipment(MessageRecord m) {
    final t = _digits(m.body);
    if (m.outgoing || MessageLogic.risk(t, sender: m.sender).suspicious) return null;
    final tipax = t.contains('تیپاکس');
    if (!tipax && !t.contains('پست')) return null;
    final match = RegExp(r'(?:کد|شماره|بارکد|رهگیری|پیگیری|مرسوله)[^0-9\n]{0,24}([0-9]{8,24})(?![0-9])').firstMatch(t);
    if (match == null) return null;
    return (code: match[1]!, site: Uri.parse(tipax ? 'https://tipaxco.com/tracking' : 'https://tracking.post.ir/'));
  }

  static ({String title, DateTime? start})? calendar(MessageRecord m) {
    if (MessageLogic.risk(m.body, sender: m.sender).suspicious) return null;
    final t = _digits(m.body);
    final cue = RegExp('قسط|قبض|سررسید|جلسه|قرار|نوبت').firstMatch(t);
    if (cue == null) return null;
    final anchor = m.date.toLocal();
    DateTime? day;
    final j = RegExp(r'\b(1[34][0-9]{2})[-/](\d{1,2})[-/](\d{1,2})\b').firstMatch(t);
    if (j != null) {
      final year = int.parse(j[1]!), month = int.parse(j[2]!), date = int.parse(j[3]!);
      if (month < 1 || month > 12 || date < 1 || date > 31) return null;
      final g = Jalali.toGregorian(year, month, date);
      final check = Jalali.fromGregorian(g[0], g[1], g[2]);
      if (check[0] != year || check[1] != month || check[2] != date) return null;
      day = DateTime(g[0], g[1], g[2]);
    } else if (t.contains('فردا') || t.contains('امروز')) {
      final offset = t.contains('پس فردا') || t.contains('پس‌فردا') ? 2 : t.contains('فردا') ? 1 : 0;
      day = DateTime(anchor.year, anchor.month, anchor.day + offset);
    }
    final clock = RegExp(r'ساعت\s*([0-9]{1,2})(?::([0-9]{2}))?').firstMatch(t);
    if (day != null) {
      final h = int.tryParse(clock?[1] ?? '') ?? 9;
      final min = int.tryParse(clock?[2] ?? '') ?? 0;
      if (h >= 24 || min >= 60) return null;
      day = DateTime(day.year, day.month, day.day, h, min);
    }
    return (title: 'یادآوری ${cue[0]}', start: day);
  }
}
