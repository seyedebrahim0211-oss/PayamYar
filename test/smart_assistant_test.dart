import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/smart_assistant.dart';

void main() {
  test('suggests contextual greetings without sending', () {
    final replies = SmartAssistant.suggestReplies('سلام، خوبی؟');
    expect(replies, isNotEmpty);
    expect(replies.length, lessThanOrEqualTo(3));
    expect(replies.first, contains('سلام'));
  });
  test('suggests polite confirmation for a meeting', () {
    expect(SmartAssistant.suggestReplies('فردا ساعت ۱۰ جلسه داریم'), contains('زمان را تأیید می‌کنم'));
  });
  test('does not pretend to understand unfamiliar messages', () {
    expect(SmartAssistant.suggestReplies('نکته نامرتبط'), isEmpty);
  });
}
