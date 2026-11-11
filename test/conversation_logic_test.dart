import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/conversation_logic.dart';
void main() {
  test('Iranian numbers are normalized into one thread', () {
    final m = [
      MessageRecord(sender:'09123456789', body:'اول', date:DateTime(2026,1,1)),
      MessageRecord(sender:'+989123456789', body:'دوم', date:DateTime(2026,1,2)),
    ];
    expect(ConversationLogic.group(m).length, 1);
    expect(ConversationLogic.group(m).first.latest.body, 'دوم');
  });
  test('different senders are separated', () {
    final m = [
      MessageRecord(sender:'BankA', body:'اول', date:DateTime(2026)),
      MessageRecord(sender:'BankB', body:'دوم', date:DateTime(2026)),
    ];
    expect(ConversationLogic.group(m).length, 2);
  });
}
