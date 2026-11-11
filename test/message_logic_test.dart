import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/message_logic.dart';
void main() {
  test('bank category', () {
    final m=MessageRecord(sender:'بانک',body:'واریز',date:DateTime(2026));
    expect(MessageLogic.category(m),MessageCategory.banking);
  });
  test('suspicious link warning', () {
    expect(MessageLogic.suspicious('حساب شما مسدود لینک https://example.com'),isTrue);
  });
  test('search is filtered', () {
    final records=[MessageRecord(sender:'Ali',body:'hello',date:DateTime(2026))];
    expect(MessageLogic.search(records,'hello').length,1);
    expect(MessageLogic.search(records,'notfound'),isEmpty);
  });
}
