import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/message_search.dart';

void main() {
  test('Persian and Arabic text is normalized', () {
    expect(MessageSearch.matches('نامه‌ای درباره کتاب', 'كتاب'), isTrue);
    expect(MessageSearch.matches('آزمون شماره ۱۲۳', '123'), isTrue);
    expect(MessageSearch.matches('سلام و درود', 'درود سلام'), isTrue);
    expect(MessageSearch.matches('سلام', 'خداحافظ'), isFalse);
  });
}
