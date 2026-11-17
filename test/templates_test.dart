import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/templates.dart';
import 'package:payamyar/message_search.dart';

void main() {
  test('built-in template library has diverse and original categorized content', () {
    expect(builtInTemplates.length, greaterThanOrEqualTo(15));
    final samples = builtInTemplates.values.expand((list) => list).toList();
    expect(samples.length, greaterThanOrEqualTo(120));
    expect(samples.every((text) => text.trim().isNotEmpty), isTrue);
    expect(samples.toSet().length, samples.length);
    expect(builtInTemplates['رزرو و نوبت'], isNotEmpty);
    expect(builtInTemplates['پیگیری و پشتیبانی'], isNotEmpty);
  });

  test('global ready-message search normalizes Persian and Arabic characters', () {
    final matches = builtInTemplates.values.expand((list) => list)
      .where((text) => MessageSearch.matches(text, 'پشتيباني')).toList();
    expect(matches, isNotEmpty);
  });
}
