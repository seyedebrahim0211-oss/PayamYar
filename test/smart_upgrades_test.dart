import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/conversation_insights.dart';
import 'package:payamyar/jalali.dart';
import 'package:payamyar/message_logic.dart';

void main() {
  group('phishing heuristics', () {
    test('link hiding its real host behind @ is flagged', () {
      final r = MessageLogic.risk('حساب شما https://bmi.ir@evil-login.top/a');
      expect(r.suspicious, isTrue);
    });
    test('punycode look-alike domain is flagged', () {
      expect(MessageLogic.risk('ورود: https://xn--80ak6aa92e.com').suspicious, isTrue);
    });
    test('request for card secrets is flagged', () {
      expect(MessageLogic.risk('لطفا رمز دوم و cvv2 کارت را ارسال کنید').suspicious, isTrue);
    });
    test("a bank's own warning about card secrets is not flagged", () {
      expect(MessageLogic.risk('بانک ملت: هرگز رمز دوم خود را برای کسی ارسال نکنید').suspicious, isFalse);
    });
  });

  group('awaiting reply', () {
    final now = DateTime(2026, 11, 20, 18);
    MessageRecord inMsg(String body, DateTime at) =>
        MessageRecord(sender: '09121234567', body: body, date: at);

    test('unanswered personal question older than 2h', () {
      expect(ConversationInsights.awaitingReply(
          [inMsg('فردا میای جلسه؟', now.subtract(const Duration(hours: 3)))], now: now), isTrue);
    });
    test('recent question is not yet flagged', () {
      expect(ConversationInsights.awaitingReply(
          [inMsg('فردا میای؟', now.subtract(const Duration(minutes: 20)))], now: now), isFalse);
    });
    test('answered conversation is not flagged', () {
      expect(ConversationInsights.awaitingReply([
        MessageRecord(sender: '09121234567', body: 'آره', date: now.subtract(const Duration(hours: 1)), outgoing: true),
        inMsg('فردا میای؟', now.subtract(const Duration(hours: 5))),
      ], now: now), isFalse);
    });
    test('verification codes are never flagged', () {
      expect(ConversationInsights.awaitingReply(
          [inMsg('کد تایید شما 4821 است؟', now.subtract(const Duration(hours: 3)))], now: now), isFalse);
    });
  });

  test('calendar day difference is DST-safe and ignores time of day', () {
    expect(Jalali.dayDiff(DateTime(2026, 3, 30, 0, 30), DateTime(2026, 3, 29, 23, 50)), 1);
    expect(Jalali.dayDiff(DateTime(2026, 3, 29, 23, 50), DateTime(2026, 3, 29, 0, 10)), 0);
  });
}
