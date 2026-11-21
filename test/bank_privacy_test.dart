import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/bank_privacy.dart';
import 'package:payamyar/message_logic.dart';

void main() {
  test('bank messages conceal amounts, account digits and balances in all scripts', () {
    const text = 'بانک ملت - موجودی ۱۲٬۳۴۵٬۶۷۸ ریال؛ حساب 1234-5678';
    final hidden = BankPrivacy.preview(MessageCategory.banking, text);
    expect(hidden, isNot(contains('۱۲٬۳۴۵٬۶۷۸')));
    expect(hidden, isNot(contains('1234')));
    expect(hidden, contains('••••'));
    expect(hidden, contains('موجودی'));
    expect(BankPrivacy.preview(MessageCategory.personal, text), text);
  });

  test('single or grouped digits cannot accidentally disclose bank amounts', () {
    expect(BankPrivacy.conceal('موجودی: ۹۹ تومان'), contains('••••'));
    expect(BankPrivacy.conceal('موجودی: 123,456 تومان'), isNot(contains('123')));
    expect(BankPrivacy.conceal('رمز: ۴۵۶۷'), isNot(contains('۴۵۶۷')));
  });
}
