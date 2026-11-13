/// On-device reply suggestions. Never auto-sends or uploads SMS content.
/// Recommendations are intentionally conservative and require an explicit send.
class SmartAssistant {
  static String _norm(String s) => s.trim().toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک').replaceAll('‌', ' ');

  static bool _any(String v, List<String> words) => words.any(v.contains);

  /// Up to three short replies for the latest incoming personal message.
  /// [now] picks greetings suited to the time of day.
  static List<String> suggestReplies(String incoming, {DateTime? now}) {
    final v = _norm(incoming);
    if (v.isEmpty) return const [];
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
    if (_any(v, ['عید', 'نوروز', 'سال نو'])) {
      return const ['عید شما هم مبارک 🌷', 'سال خوبی داشته باشید', 'ممنون، همچنین'];
    }
    if (_any(v, ['ممنون', 'مرسی', 'تشکر', 'سپاس', 'دستت درد نکنه'])) {
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
