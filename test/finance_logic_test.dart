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
  test('latest explicit account balances remain separate and use newest SMS', () {
    final rows = [
      MessageRecord(sender: 'بانک نمونه',
        body: 'حساب 12345678 موجودی: ۱,۲۰۰,۰۰۰ تومان',
        date: DateTime(2026, 11, 1)),
      MessageRecord(sender: 'بانک نمونه',
        body: 'حساب 12345678 موجودی: ۱,۵۰۰,۰۰۰ تومان',
        date: DateTime(2026, 11, 2)),
      MessageRecord(sender: 'بانک نمونه',
        body: 'حساب 87654321 موجودی: ۲,۰۰۰,۰۰۰ ریال',
        date: DateTime(2026, 11, 1)),
      MessageRecord(sender: 'بانک نمونه', body: 'برداشت ۳۰۰,۰۰۰ تومان',
        date: DateTime(2026, 11, 3)),
    ];
    final result = FinanceLogic.latestBalances(rows);
    expect(result.length, 2);
    expect(result.first.lastFour, '5678');
    expect(result.first.amountTomans, 1500000);
    expect(result.last.lastFour, '4321');
    expect(result.last.amountTomans, 200000);
  });
  test('balance requires currency and is not derived from withdrawals', () {
    final rows = [
      MessageRecord(sender: 'بانک', body: 'موجودی: ۱۲۰۰۰۰',
        date: DateTime(2026)),
      MessageRecord(sender: 'بانک', body: 'برداشت ۲۰۰۰۰ ریال',
        date: DateTime(2026)),
    ];
    expect(FinanceLogic.latestBalances(rows), isEmpty);
  });

}
