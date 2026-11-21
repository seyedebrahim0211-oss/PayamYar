import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/screens/dialect_card.dart';

void main() {
  test('daily word requires a public word, meaning and first-party audio', () {
    String card(String kind, String url) => '<article data-kind="$kind"><h3>اَغال</h3>'
      '<p class="gy-mean">آغل</p><button data-au="$url"></button></article>';
    const sound = 'https://honarmardomi.ir/static/u/example.mp3';
    expect(dialectEntries(card('word', sound) + card('word', 'https://example.com/a.mp3') +
      card('word', '') + card('proverb', sound)), [['اَغال', 'آغل', sound]]);
  });
}
