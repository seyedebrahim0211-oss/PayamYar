import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/jalali.dart';
import 'package:payamyar/message_logic.dart';

void main() {
  test('Gregorian to Jalali conversion', () {
    expect(Jalali.fromGregorian(2026, 11, 11), [1405, 8, 20]);
    expect(Jalali.fromGregorian(2025, 3, 21), [1404, 1, 1]);
    expect(Jalali.fromGregorian(2024, 3, 20), [1403, 1, 1]);
  });
  test('Short list dates', () {
    final now = DateTime(2026, 11, 11, 18);
    expect(Jalali.short(DateTime(2026, 11, 11, 9, 5), now: now), '۰۹:۰۵');
    expect(Jalali.short(DateTime(2026, 11, 10, 9), now: now), 'دیروز');
    expect(Jalali.short(DateTime(2026, 10, 1), now: now), '۹ مهر');
    expect(Jalali.short(DateTime(2024, 3, 20), now: now), '۱۴۰۳/۰۱/۰۱');
  });
  test('Verification code detection', () {
    expect(MessageLogic.otp('کد تأیید شما: ۴۸۲۱۳'), '48213');
    expect(MessageLogic.otp('Your code is 123456'), '123456');
    expect(MessageLogic.otp('رمز پویا 9876 معتبر تا 2 دقیقه'), '9876');
    expect(MessageLogic.otp('سلام، فردا ساعت ۱۰ جلسه داریم.'), isNull);
  });
}
