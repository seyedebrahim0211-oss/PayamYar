/// On-device Persian text editor: spelling, half-spaces, punctuation and a more formal tone.
/// Rule-based (no internet, no AI): it fixes common, unambiguous cases and leaves the rest untouched.
class TextPolish {
  static const _zwnj = '‌';
  // Persian/Arabic letters, diacritics and Persian digits; punctuation marks are deliberately excluded.
  static const _fa = r'ء-غـ-ْٮ-ۓ۰-۹';

  static String _word(String w) => '(?<![$_fa$_zwnj])$w(?![$_fa$_zwnj])';

  static String _replaceWords(String text, Map<String, String> words) {
    var s = text;
    // Longest first, so "یه کم" is handled before "یه".
    final keys = words.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final from in keys) {
      if (s.contains(from)) s = s.replaceAll(RegExp(_word(RegExp.escape(from))), words[from]!);
    }
    return s;
  }

  /// Common misspellings and missing tanvin.
  static const spellingWords = <String, String>{
    'راجب': 'راجع به', 'حتمن': 'حتماً', 'لطفن': 'لطفاً', 'اصلن': 'اصلاً', 'واقعن': 'واقعاً',
    'مثلن': 'مثلاً', 'فعلن': 'فعلاً', 'بعدن': 'بعداً', 'قبلن': 'قبلاً', 'حتما': 'حتماً',
    'لطفا': 'لطفاً', 'اصلا': 'اصلاً', 'واقعا': 'واقعاً', 'مثلا': 'مثلاً', 'فعلا': 'فعلاً',
    'بعدا': 'بعداً', 'قبلا': 'قبلاً', 'حدودا': 'حدوداً', 'دقیقا': 'دقیقاً', 'معمولا': 'معمولاً',
    'کاملا': 'کاملاً', 'تقریبا': 'تقریباً', 'احتمالا': 'احتمالاً', 'سریعا': 'سریعاً', 'ضمنا': 'ضمناً',
    'خاهش': 'خواهش', 'خاهر': 'خواهر', 'مطمعن': 'مطمئن', 'مسعول': 'مسئول', 'مسعولیت': 'مسئولیت',
    'توجیح': 'توجیه', 'ترجیه': 'ترجیح', 'حظور': 'حضور', 'سپاسگذار': 'سپاسگزار', 'سپاسگذارم': 'سپاسگزارم',
    'خدمتگذار': 'خدمتگزار', 'گزاشتم': 'گذاشتم', 'گزاشت': 'گذاشت', 'میگزارم': 'می‌گذارم',
    'انشالله': 'ان‌شاءالله', 'انشاالله': 'ان‌شاءالله', 'ایشالا': 'ان‌شاءالله', 'ایشالله': 'ان‌شاءالله',
    'تشکور': 'تشکر', 'منتضر': 'منتظر', 'انتضار': 'انتظار', 'ضمینه': 'زمینه', 'علاغه': 'علاقه',
    'عذر خاهی': 'عذرخواهی', 'عذرخاهی': 'عذرخواهی', 'خوشهال': 'خوشحال', 'ناراهت': 'ناراحت',
    'استراهت': 'استراحت', 'بر علیه': 'علیه',
  };

  /// Spoken forms rewritten in standard written Persian.
  static const formalWords = <String, String>{
    'میخوام': 'می‌خواهم', 'می‌خوام': 'می‌خواهم', 'نمیخوام': 'نمی‌خواهم', 'نمی‌خوام': 'نمی‌خواهم',
    'میخوای': 'می‌خواهی', 'می‌خوای': 'می‌خواهی', 'میخواد': 'می‌خواهد', 'می‌خواد': 'می‌خواهد',
    'میتونم': 'می‌توانم', 'می‌تونم': 'می‌توانم', 'نمیتونم': 'نمی‌توانم', 'نمی‌تونم': 'نمی‌توانم',
    'میتونی': 'می‌توانی', 'می‌تونی': 'می‌توانی', 'میتونه': 'می‌تواند', 'می‌تونه': 'می‌تواند',
    'میتونید': 'می‌توانید', 'می‌تونید': 'می‌توانید', 'بتونم': 'بتوانم', 'بتونی': 'بتوانی',
    'میشه': 'می‌شود', 'می‌شه': 'می‌شود', 'نمیشه': 'نمی‌شود', 'نمی‌شه': 'نمی‌شود', 'بشه': 'بشود',
    'میگم': 'می‌گویم', 'می‌گم': 'می‌گویم', 'میگی': 'می‌گویی', 'می‌گی': 'می‌گویی',
    'میگه': 'می‌گوید', 'می‌گه': 'می‌گوید', 'بگم': 'بگویم', 'بگی': 'بگویی', 'بگه': 'بگوید',
    'میرم': 'می‌روم', 'می‌رم': 'می‌روم', 'میری': 'می‌روی', 'می‌ری': 'می‌روی', 'میره': 'می‌رود',
    'برم': 'بروم', 'بری': 'بروی', 'بره': 'برود', 'بریم': 'برویم',
    'میام': 'می‌آیم', 'می‌یام': 'می‌آیم', 'میای': 'می‌آیی', 'میاد': 'می‌آید', 'بیام': 'بیایم', 'بیای': 'بیایی',
    'میدونم': 'می‌دانم', 'می‌دونم': 'می‌دانم', 'نمیدونم': 'نمی‌دانم', 'نمی‌دونم': 'نمی‌دانم',
    'میدونی': 'می‌دانی', 'می‌دونی': 'می‌دانی', 'بدونم': 'بدانم',
    'میدم': 'می‌دهم', 'می‌دم': 'می‌دهم', 'بدم': 'بدهم',
    'میکنم': 'می‌کنم', 'میکنی': 'می‌کنی', 'میکنه': 'می‌کند', 'می‌کنه': 'می‌کند', 'بکنه': 'بکند',
    'هستش': 'است', 'نیس': 'نیست', 'هس': 'هست', 'باشه': 'باشد', 'نباشه': 'نباشد',
    'اگه': 'اگر', 'دیگه': 'دیگر', 'یه': 'یک', 'چی': 'چه', 'واسه': 'برای',
    'خونه': 'خانه', 'اون': 'آن', 'اونا': 'آن‌ها', 'اینا': 'این‌ها', 'اونجا': 'آنجا', 'همون': 'همان',
    'بهت': 'به تو', 'بهش': 'به او', 'بهم': 'به من', 'ازت': 'از تو', 'ازش': 'از او', 'باهات': 'با تو',
    'مرسی': 'سپاسگزارم', 'ممنون': 'سپاسگزارم', 'ببخشید': 'پوزش می‌خواهم', 'چطوری': 'حال شما چطور است',
    'بذار': 'بگذار', 'بزار': 'بگذار', 'نذار': 'نگذار', 'وایسا': 'بایست',
    'آره': 'بله', 'اره': 'بله', 'فک کنم': 'فکر می‌کنم', 'فک میکنم': 'فکر می‌کنم',
    'یکم': 'کمی', 'یه کم': 'کمی', 'خیلی ممنون': 'بسیار سپاسگزارم', 'زنگ بزن': 'تماس بگیرید',
    'زنگ میزنم': 'تماس می‌گیرم', 'زنگ می‌زنم': 'تماس می‌گیرم',
  };

  static const _faDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// Letters, half-spaces, spacing and punctuation.
  static String orthography(String text) {
    var s = text;
    // Arabic letter forms typed by some keyboards.
    s = s.replaceAll('ي', 'ی').replaceAll('ك', 'ک').replaceAll('ى', 'ی');
    // "می خواهم" / "نمی دانم" -> half-space; "میکنم" -> "می‌کنم" for common verb stems.
    s = s.replaceAllMapped(RegExp('(^|[^$_fa$_zwnj])(ن?می) (?=[$_fa]{2})'), (m) => '${m[1]}${m[2]}$_zwnj');
    s = s.replaceAllMapped(
      RegExp('(^|[^$_fa$_zwnj])(ن?می)(?=(?:کن|خواه|توان|شو|رو|گوی|دان|آی|ده|گیر|بین|زن|ساز|نویس|خوان|رس|فرست|گذار|آور|شناس|پرس|دار)[$_fa])'),
      (m) => '${m[1]}${m[2]}$_zwnj');
    // Plural and comparative suffixes written with a space.
    s = s.replaceAllMapped(RegExp('([$_fa]) (ها|های|هایی|هایم|هایت|هایش|هایمان|هایتان|هایشان|ترین)(?![$_fa$_zwnj])'),
      (m) => '${m[1]}$_zwnj${m[2]}');
    // "خانه ی" -> "خانه‌ی"
    s = s.replaceAllMapped(RegExp('(ه) (ی|ای)(?![$_fa$_zwnj])'), (m) => '${m[1]}$_zwnj${m[2]}');
    // Latin punctuation next to Persian text.
    s = s.replaceAllMapped(RegExp('(?<=[$_fa$_zwnj]) ?,'), (m) => '،');
    s = s.replaceAllMapped(RegExp('(?<=[$_fa$_zwnj]) ?;'), (m) => '؛');
    s = s.replaceAllMapped(RegExp('(?<=[$_fa$_zwnj]) ?\\?'), (m) => '؟');
    // Repeated marks, with or without spaces between them.
    s = s.replaceAll(RegExp('؟( *؟)+'), '؟').replaceAll(RegExp('!( *!)+'), '!').replaceAll(RegExp('،( *،)+'), '،');
    // No space before punctuation, exactly one after.
    s = s.replaceAllMapped(RegExp(' +([،؛؟!.:])'), (m) => m[1]!);
    s = s.replaceAllMapped(RegExp('([،؛؟!])(?=[$_fa])'), (m) => '${m[1]} ');
    s = s.replaceAllMapped(RegExp('(?<=[$_fa])\\.(?=[$_fa])'), (m) => '. ');
    // Repeated spaces.
    s = s.replaceAll(RegExp('[ \\t]{2,}'), ' ');
    s = s.replaceAll(RegExp(' +\\n'), '\n').replaceAll(RegExp('\\n{3,}'), '\n\n');
    // Persian digits inside Persian text; links, emails and Latin words keep their digits.
    s = s.split(RegExp('(?<=\\s)|(?=\\s)')).map((token) {
      // Phone numbers, card numbers and codes stay in Latin digits so they remain tappable and copyable.
      if (RegExp('[A-Za-z@/_]|[0-9]{5}').hasMatch(token) || !RegExp('[0-9]').hasMatch(token)) return token;
      return token.replaceAllMapped(RegExp('[0-9]'), (m) => _faDigits[int.parse(m[0]!)]);
    }).join();
    return s.trim();
  }

  static String spelling(String text) => _replaceWords(text, spellingWords);

  static String formal(String text) => _replaceWords(text, formalWords);

  /// Adds a greeting and a closing when the message has none.
  static String polite(String text) {
    var s = text.trim();
    if (s.isEmpty) return s;
    if (!RegExp('^(با )?(سلام|درود)').hasMatch(s)) s = 'سلام، وقت بخیر.\n$s';
    if (!RegExp('(تشکر|سپاس|ممنون|ارادتمند)[^\\n]*\$').hasMatch(s)) s = '$s\nبا تشکر';
    return s;
  }

  static String apply(String text, {bool fix = true, bool formalTone = false, bool politeTone = false}) {
    var s = text;
    if (fix) s = spelling(orthography(s));
    if (formalTone) s = formal(s);
    if (fix) s = orthography(s);
    if (politeTone) s = polite(s);
    return s;
  }

  /// Number of SMS parts the text is sent as, and characters left in the current part.
  static ({int parts, int remaining}) smsParts(String text) {
    if (text.isEmpty) return (parts: 0, remaining: 70);
    final unicode = text.runes.any((r) => r > 127);
    final single = unicode ? 70 : 160, multi = unicode ? 67 : 153;
    final length = text.length;
    if (length <= single) return (parts: 1, remaining: single - length);
    final parts = (length / multi).ceil();
    return (parts: parts, remaining: parts * multi - length);
  }
}
