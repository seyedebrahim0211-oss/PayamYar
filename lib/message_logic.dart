enum MessageCategory { personal, banking, service, advertising }

/// Phishing assessment of one message: [score] ≥ 2 is shown as a warning.
class RiskReport {
  final int score;
  final List<String> reasons;
  const RiskReport(this.score, this.reasons);
  bool get suspicious => score >= 2;
}
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
  // ── phishing heuristics (Iranian SMS scams: fake سنا/ابلاغیه، یارانه، سهام عدالت، جریمه) ──
  static final _lure = RegExp(
      r'ابلاغیه|ثنا|سامانه عدالت|شکایت|احضار|جریمه|خلافی|یارانه|سهام عدالت|کالابرگ|وام فوری|'
      r'برنده|جایزه|قرعه.?کشی|مسدود|تعلیق|بازگشت وجه|پرداخت فوری|فقط امروز|آخرین مهلت|تایید هویت|احراز هویت');
  static final _urlRe = RegExp(r'(?:https?://)?(?:www\.)?([a-z0-9-]+(?:\.[a-z0-9-]+)+)(?:/[^\s]*)?', caseSensitive: false);
  static const _shorteners = {'bit.ly', 'b2n.ir', 'yun.ir', 'tinyurl.com', 'goo.gl', 'cutt.ly', 'shorturl.at', 'is.gd', 't.ly', 'rb.gy'};
  static const _official = {
    'adliran.ir', 'my.gov.ir', 'shaparak.ir', 'sena.ir', 'eadl.ir', 'post.ir', 'irica.gov.ir', 'iran.gov.ir',
    'snapp.ir', 'digikala.com', 'divar.ir', 'bmi.ir', 'bankmellat.ir', 'sb24.ir', 'bpi.ir', 'tejaratbank.ir',
    'sahamedalat.ir', 'samanehsaman.ir', 'mcls.gov.ir', 'rahvar120.ir', 'ecitizen.ir',
  };
  /// Distinctive brand words that scammers copy into look-alike domains.
  static const _brands = ['adliran', 'shaparak', 'eadl', 'irica', 'digikala', 'divar', 'bankmellat', 'tejaratbank',
    'sb24', 'sahamedalat', 'yaraneh', 'sana-', 'sakhad', 'rahvar'];
  static final _apk = RegExp(r'\.apk\b|نصب (?:برنامه|اپلیکیشن)|دانلود (?:برنامه|اپلیکیشن)');
  static final _ipLink = RegExp(r'https?://\d{1,3}(?:\.\d{1,3}){3}');

  static MessageCategory category(MessageRecord m) {
    final s = ('${m.sender} ${m.body}').toLowerCase();
    if (_banking.hasMatch(s)) return MessageCategory.banking;
    if (_advertising.hasMatch(s)) return MessageCategory.advertising;
    if (_service.hasMatch(s)) return MessageCategory.service;
    return MessageCategory.personal;
  }

  static bool suspicious(String body) => risk(body).suspicious;

  /// Explains why a message looks like phishing. Purely local, rule-based; never uploads text.
  static RiskReport risk(String body, {String sender = ''}) {
    final s = body.toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک');
    final reasons = <String>[];
    var score = 0;
    final hasLink = _link.hasMatch(s);
    final hosts = [
      for (final m in _urlRe.allMatches(s))
        if (m.group(1)!.contains(RegExp(r'[a-z]'))) m.group(1)!.toLowerCase(), // skip amounts like 1.500.000
    ];
    bool official(String h) => _official.any((o) => h == o || h.endsWith('.$o'));
    final unknownLink = hosts.any((h) => !official(h));
    if (_scam.hasMatch(s) && hasLink) {
      score += 3;
      reasons.add('ادعای جایزه، ابلاغیه یا مسدودی همراه با لینک');
    } else if (_lure.hasMatch(s) && unknownLink) {
      score += 2;
      reasons.add('موضوع حساس (ابلاغیه، یارانه، جریمه، مسدودی…) همراه با لینک ناشناس');
    }
    for (final host in hosts) {
      if (_shorteners.contains(host)) {
        score += 2;
        reasons.add('لینک کوتاه‌شده که مقصد واقعی را پنهان می‌کند ($host)');
      }
      // Official brand names inside a foreign domain: e.g. adliran-sabt.xyz, shaparak-ir.top
      final looksOfficial = _brands.any(host.contains);
      if (looksOfficial && !official(host)) {
        score += 3;
        reasons.add('دامنه جعلی شبیه سایت رسمی ($host)');
      }
      if (RegExp(r'\.(xyz|top|click|link|info|online|site|buzz|icu)$').hasMatch(host)) {
        score += 1;
        reasons.add('دامنه کم‌اعتبار ($host)');
      }
    }
    if (_ipLink.hasMatch(s)) {
      score += 2;
      reasons.add('لینک با آدرس IP به‌جای نام سایت');
    }
    if (_apk.hasMatch(s) && hasLink) {
      score += 2;
      reasons.add('درخواست نصب برنامه از لینک (احتمال بدافزار)');
    }
    // Personal mobile numbers do not send official notices.
    if (RegExp(r'^(\+98|0)?9\d{9}$').hasMatch(sender.replaceAll(' ', '')) && _lure.hasMatch(s) && unknownLink) {
      score += 1;
      reasons.add('پیام رسمی از شماره موبایل شخصی');
    }
    return RiskReport(score, reasons);
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
