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
  test('short holiday keyword does not fire inside other words', () {
    expect(SmartAssistant.suggestReplies('عید شما مبارک'), contains('عید شما هم مبارک 🌷'));
    expect(SmartAssistant.suggestReplies('سعید هم میاد'), isNot(contains('عید شما هم مبارک 🌷')));
    expect(SmartAssistant.suggestReplies('بعید میدونم بیاد'), isNot(contains('عید شما هم مبارک 🌷')));
  });
  test('does not pretend to understand unfamiliar messages', () {
    expect(SmartAssistant.suggestReplies('نکته نامرتبط'), isEmpty);
  });
}
