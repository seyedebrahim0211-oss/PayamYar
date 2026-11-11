import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/finance_logic.dart';
import 'package:payamyar/message_logic.dart';

void main() {
  test('deposit with Persian numerals', () {
    final m = MessageRecord(sender: 'بانک', body: 'واریز ۲۵۰,۰۰۰ تومان', date: DateTime(2026));
    expect(FinanceLogic.parse(m)?.amountTomans, 250000);
    expect(FinanceLogic.parse(m)?.kind, FinanceKind.deposit);
  });
  test('Rial conversion', () {
    final m = MessageRecord(sender: 'بانک', body: 'برداشت 100,000 ریال', date: DateTime(2026));
    expect(FinanceLogic.parse(m)?.amountTomans, 10000);
  });
  test('personal messages excluded', () {
    final m = MessageRecord(sender: 'دوست', body: '۲۰۰۰ تومان خرید', date: DateTime(2026));
    expect(FinanceLogic.parse(m), isNull);
  });
  test('number formatting', () {
    expect(FinanceLogic.formatTomans(1250000), '1,250,000 تومان');
  });
}
