/// Persian (Jalali) calendar and Persian-digit formatting for message dates.
class Jalali {
  static const months = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
  static const weekdays = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];

  /// Converts a Gregorian date to [year, month, day] in the Jalali calendar.
  static List<int> fromGregorian(int gy, int gm, int gd) {
    const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    final gy2 = gm > 2 ? gy + 1 : gy;
    var days = 355666 + (365 * gy) + ((gy2 + 3) ~/ 4) - ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) + gd + gdm[gm - 1];
    var jy = -1595 + (33 * (days ~/ 12053));
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    final int jm, jd;
    if (days < 186) {
      jm = 1 + days ~/ 31;
      jd = 1 + (days % 31);
    } else {
      jm = 7 + (days - 186) ~/ 30;
      jd = 1 + ((days - 186) % 30);
    }
    return [jy, jm, jd];
  }

  /// Converts a Jalali date to [year, month, day] in the Gregorian calendar.
  static List<int> toGregorian(int jy, int jm, int jd) {
    final jy2 = jy + 1595;
    var days = -355668 + (365 * jy2) + ((jy2 ~/ 33) * 8) + (((jy2 % 33) + 3) ~/ 4) + jd +
        (jm < 7 ? (jm - 1) * 31 : ((jm - 7) * 30) + 186);
    var gy = 400 * (days ~/ 146097);
    days %= 146097;
    if (days > 36524) {
      gy += 100 * (--days ~/ 36524);
      days %= 36524;
      if (days >= 365) days++;
    }
    gy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      gy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    var gd = days + 1;
    final leap = (gy % 4 == 0 && gy % 100 != 0) || (gy % 400 == 0);
    final monthDays = [0, 31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var gm = 0;
    for (gm = 1; gm <= 12 && gd > monthDays[gm]; gm++) {
      gd -= monthDays[gm];
    }
    return [gy, gm, gd];
  }

  static String digits(Object value) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    return value.toString().split('').map((c) {
      final i = c.codeUnitAt(0) - 48;
      return i >= 0 && i <= 9 ? fa[i] : c;
    }).join();
  }

  static String time(DateTime d) =>
      digits('${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}');

  /// "۱۴:۰۵" today, "دیروز", weekday within a week, "۲۰ آبان" this year, otherwise "۱۴۰۴/۰۸/۲۰".
  static String short(DateTime d, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = start.difference(day).inDays;
    if (diff <= 0) return time(d);
    if (diff == 1) return 'دیروز';
    if (diff < 7) return weekdays[d.weekday - 1];
    final j = fromGregorian(d.year, d.month, d.day);
    final jt = fromGregorian(today.year, today.month, today.day);
    if (j[0] == jt[0]) return '${digits(j[2])} ${months[j[1] - 1]}';
    return digits('${j[0]}/${j[1].toString().padLeft(2, '0')}/${j[2].toString().padLeft(2, '0')}');
  }

  /// Day header inside a conversation: "امروز", "دیروز" or "شنبه ۲۰ آبان ۱۴۰۵".
  static String dayHeader(DateTime d, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final diff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'امروز';
    if (diff == 1) return 'دیروز';
    final j = fromGregorian(d.year, d.month, d.day);
    return '${weekdays[d.weekday - 1]} ${digits(j[2])} ${months[j[1] - 1]} ${digits(j[0])}';
  }
}
