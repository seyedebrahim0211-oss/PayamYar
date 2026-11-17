import '../message_logic.dart';
import '../message_search.dart';

/// Offline, rule-based SMS insights. Never transmits message text or contacts.
enum SmartSmsCategory { personal, financial, verification, service, promotion, suspicious }

class SmartSmsInsight {
  final SmartSmsCategory category;
  final int riskScore;
  final List<String> reasons;
  final bool containsOneTimeCode;
  const SmartSmsInsight(this.category, this.riskScore, this.reasons, this.containsOneTimeCode);
  bool get needsReview => riskScore >= 2;
}

class SmartSmsEngine {
  SmartSmsEngine._();

  static final _financial = RegExp(r'بانک|واریز|برداشت|موجودی|مانده|تراکنش|پایا|ساتنا|کارت به کارت');
  static final _verification = RegExp(
      r'رمز پویا|رمز یک بار مصرف|رمز یکبار مصرف|کد تایید|کد ورود|کد فعال سازی|otp|verification code');
  static final _numericCode = RegExp(r'(^|[^0-9])[0-9]{4,8}([^0-9]|$)');
  static final _promotion = RegExp(r'تخفیف|حراج|فروش ویژه|پیشنهاد ویژه|لغو 11');
  static final _service = RegExp(r'مرسوله|قبض|بسته اینترنت|نوبت|پیگیری|اطلاعیه');

  /// Classifies a message and explains suspicious patterns without cloud AI.
  /// The heuristic is advisory, not a guarantee that a link or sender is safe.
  static SmartSmsInsight analyze(String sender, String body) {
    final normalized = MessageSearch.normalize(body);
    final risk = MessageLogic.risk(body, sender: sender);
    final oneTimeCode = _verification.hasMatch(normalized) && _numericCode.hasMatch(normalized);
    final category = risk.suspicious
        ? SmartSmsCategory.suspicious
        : oneTimeCode
            ? SmartSmsCategory.verification
            : _financial.hasMatch(normalized)
                ? SmartSmsCategory.financial
                : _promotion.hasMatch(normalized)
                    ? SmartSmsCategory.promotion
                    : _service.hasMatch(normalized)
                        ? SmartSmsCategory.service
                        : SmartSmsCategory.personal;
    return SmartSmsInsight(category, risk.score, risk.reasons, oneTimeCode);
  }

  /// An OTP older than one day is a cleanup candidate; no automatic deletion.
  static bool isOldVerification(String sender, String body, DateTime date,
      {DateTime? now}) {
    final age = (now ?? DateTime.now()).difference(date);
    return age >= const Duration(hours: 24) &&
        analyze(sender, body).containsOneTimeCode;
  }
}
