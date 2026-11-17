import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/smart/smart_sms_engine.dart';

void main() {
  test('contact name is reused for normalized Iranian numbers', () {
    final store = AppStore(android: false);
    store.names['09121234567'] = 'علی رضایی';
    expect(store.displayName('+989121234567'), 'علی رضایی');
    expect(store.displayName('00989121234567'), 'علی رضایی');
    expect(store.displayName('۰۹۱۲۱۲۳۴۵۶۷'), 'علی رضایی');
    expect(store.displayName('09121111111'), '09121111111');
    store.dispose();
  });

  test('offline smart engine flags suspicious links without trusting clean labels', () {
    final suspicious = SmartSmsEngine.analyze('09121234567',
      'برای دریافت ابلاغیه قضایی و پرداخت فوری وارد https://adliran-verification.xyz شوید');
    expect(suspicious.needsReview, isTrue);
    expect(suspicious.category, SmartSmsCategory.suspicious);
    expect(suspicious.reasons, isNotEmpty);
    final benign = SmartSmsEngine.analyze('09121234567', 'سلام، فردا جلسه داریم');
    expect(benign.category, SmartSmsCategory.personal);
    expect(benign.needsReview, isFalse);
  });

  test('old OTPs are identified but never deleted', () {
    final now = DateTime(2026, 11, 17, 14);
    final recent = DateTime(2026, 11, 17, 13);
    final old = DateTime(2026, 11, 15);
    const body = 'کد تأیید ورود شما: ۱۲۳۴۵';
    expect(SmartSmsEngine.analyze('1000', body).containsOneTimeCode, isTrue);
    expect(SmartSmsEngine.isOldVerification('1000', body, recent, now: now), isFalse);
    expect(SmartSmsEngine.isOldVerification('1000', body, old, now: now), isTrue);
  });
}
