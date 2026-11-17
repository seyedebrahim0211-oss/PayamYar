import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/message_search.dart';

void main() {
  test('normalized index terms work with cross-script digits and independent words', () {
    final docs = [
      MessageSearch.normalize('جلسهٔ كاری شنبه ١٢:٣٠'),
      MessageSearch.normalize('ملاقات ساعت ۱۳:۰۰'),
    ];
    final terms = MessageSearch.terms('کاری 12');
    expect(docs.any((doc) => MessageSearch.containsTerms(doc, terms)), isTrue);
    expect(docs.any((doc) => MessageSearch.containsTerms(doc, MessageSearch.terms('ناموجود'))), isFalse);
    expect(MessageSearch.terms('  '), isEmpty);
    expect(MessageSearch.containsTerms(docs.first, const []), isFalse);
  });

  test('Persian and Arabic text is normalized', () {
    expect(MessageSearch.matches('نامه‌ای درباره کتاب', 'كتاب'), isTrue);
    expect(MessageSearch.matches('آزمون شماره ۱۲۳', '123'), isTrue);
    expect(MessageSearch.matches('سلام و درود', 'درود سلام'), isTrue);
    expect(MessageSearch.matches('سلام', 'خداحافظ'), isFalse);
  });
}
