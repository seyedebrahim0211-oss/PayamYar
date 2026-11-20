import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/recipient_suggestions.dart';
import 'package:payamyar/search_highlight.dart';

void main() {
  test('highlight preserves emoji, Arabic spelling and grouped Persian digits', () {
    const text = '🐦 كِتاب ۱۲٬۳۴۵';
    final span = searchHighlight(text, 'کتاب 12345');
    expect(span.toPlainText(), text);
    expect(span.children!.where((s) => s.style != null).map((s) => s.toPlainText()),
      ['كِتاب', '۱۲٬۳۴۵']);
  });

  test('recipient picker combines Persian name and digits and accepts international numbers', () {
    final contacts = [
      {'name': 'علي كريمي', 'number': '09120000001'},
      {'name': 'علی احمدی', 'number': '09120000002'},
    ];
    expect(RecipientSuggestions.rank(contacts, {}, 'کریمی ۰۰۱'), [contacts.first]);
    expect(RecipientSuggestions.rank(contacts, {}, '+۹۸۹۱۲۰۰۰۰۰۰۲'), [contacts.last]);
  });
}
