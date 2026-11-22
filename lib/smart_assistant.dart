/// On-device reply suggestions. Never auto-sends or uploads SMS content.
/// Recommendations are intentionally conservative and require an explicit send.
class SmartAssistant {
  static String _norm(String s) => s.trim().toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک').replaceAll('‌', ' ');

  static bool _any(String v, List<String> words) => words.any(v.contains);

  /// Whole-word match, so short keywords do not fire inside other words
  /// (e.g. «عید» inside the name «سعید» or inside «بعید»).
  static bool _anyWord(String v, List<String> words) => words.any((w) =>
      RegExp('(^|[^\\u0600-\\u06FF])${RegExp.escape(w)}(\$|[^\\u0600-\\u06FF])').hasMatch(v));

  /// Up to three short replies for the latest incoming personal message.
  /// [now] picks greetings suited to the time of day.
  static List<String> suggestReplies(String incoming, {DateTime? now, int tone = 0}) {
    final v = _norm(incoming);
    if (v.isEmpty) return const [];
    if (_any(v, ['یک بارمصرف', 'یک بار مصرف', 'یکبارمصرف', 'مانده حساب', 'لغو ۱۱', 'لغو 11'])) return const [];
    final arrival = RegExp(r'ساعت\s+([۰-۹0-9:٫]+|یک|دو|سه|چهار|پنج|شش|هفت|هشت|نه|ده)\s+می\s*رسی').firstMatch(v);
    if (arrival != null) {
      return ['بله، ساعت ${arrival.group(1)} می‌رسم', 'کمی دیرتر می‌رسم', tone == 1 ? 'زمان دقیق را اطلاع می‌دهم' : 'هنوز قطعی نیست، خبر می‌دم'];
    }
    final hour = (now ?? DateTime.now()).hour;

    // Verification codes and money requests are never answered by suggestion.
    if (RegExp(r'(کد|رمز)\s*(تایید|تأیید|یکبار|پویا)').hasMatch(v)) return const [];
    if (_any(v, ['شماره کارت', 'کارت به کارت', 'رمز دوم', 'cvv2'])) {
      return const ['تماس می‌گیرم تا مطمئن شوم', 'از طریق تماس صحبت کنیم', 'لطفاً صبر کنید بررسی کنم'];
    }
    if (_any(v, ['تولدت مبارک', 'تولد مبارک', 'تبریک'])) {
      return const ['خیلی ممنونم، لطف دارید 🌹', 'سپاسگزارم 🙏', 'ممنون که یادم بودید ❤️'];
    }
    if (_any(v, ['تسلیت', 'غم آخرتان', 'روحش شاد', 'خدا رحمت'])) {
      return const ['ممنون از همدردی شما 🙏', 'لطف دارید', 'خدا رحمت کند'];
    }
    if (_anyWord(v, ['عید', 'عیدت', 'عیدتون', 'نوروز', 'سال نو', 'سال نوتون'])) {
      return const ['عید شما هم مبارک 🌷', 'سال خوبی داشته باشید', 'ممنون، همچنین'];
    }
    if (_any(v, ['ممنون', 'مرسی', 'تشکر', 'سپاس', 'دستت درد نکنه'])) {
      if (tone == 2) return const ['خواهش می‌کنم', 'خوشحالم که کمک کرد', 'قابلی نداشت'];
      if (tone == 1) return const ['خواهش می‌کنم', 'خوشحالم که مفید بود', 'از لطف شما ممنونم'];
      return const ['خواهش می‌کنم 🌹', 'لطف دارید', 'انجام وظیفه بود'];
    }
    if (_any(v, ['ببخشید', 'عذر میخوام', 'عذرخواهی', 'شرمنده'])) {
      return const ['اشکالی ندارد', 'خواهش می‌کنم، پیش می‌آید', 'مهم نیست 🌷'];
    }
    if (_any(v, ['جلسه', 'ساعت', 'قرار', 'فردا', 'وقت داری'])) {
      return const ['زمان را تأیید می‌کنم', 'ممنون، هماهنگ می‌کنم', 'اجازه بدهید بررسی کنم'];
    }
    if (_any(v, ['کجایی', 'کجا', 'آدرس', 'موقعیت', 'لوکیشن'])) {
      return const ['موقعیت را برایتان می‌فرستم', 'تا چند دقیقه دیگر خبر می‌دهم', 'لطفاً موقعیت دقیق را بفرستید'];
    }
    if (_any(v, ['رسیدی', 'رسیدید', 'کی میرسی', 'کی می‌رسی'])) {
      return const ['رسیدم 👍', 'در راهم، تا چند دقیقه دیگر', 'هنوز نرسیده‌ام'];
    }
    if (_any(v, ['زنگ بزن', 'تماس بگیر', 'تماس بگیرید', 'جواب نمیدی'])) {
      return const ['چند دقیقه دیگر تماس می‌گیرم', 'الان نمی‌توانم صحبت کنم', 'حتماً، الان تماس می‌گیرم'];
    }
    if (_any(v, ['سلام', 'درود'])) {
      final greet = hour < 11 ? 'سلام، صبح بخیر ☀️' : hour >= 19 ? 'سلام، شب بخیر 🌙' : 'سلام، وقت شما بخیر 🌷';
      return [greet, 'سلام، خوشحالم از پیامتان', 'سلام، در خدمتم'];
    }
    if (_any(v, ['شب بخیر', 'شبت بخیر'])) return const ['شب شما هم بخیر 🌙', 'خوب بخوابید', 'شب خوش'];
    if (_any(v, ['صبح بخیر'])) return const ['صبح شما هم بخیر ☀️', 'روز خوبی داشته باشید', 'صبح بخیر 🌷'];
    if (v.contains('؟') || v.contains('?')) {
      return const ['الان بررسی می‌کنم', 'کمی بعد اطلاع می‌دهم', 'لطفاً بیشتر توضیح دهید'];
    }
    return const [];
  }
}
