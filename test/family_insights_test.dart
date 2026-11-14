import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/contacts/family_screen.dart';
import 'package:payamyar/conversation_insights.dart';
import 'package:payamyar/message_logic.dart';

void main() {
  test('relationship suggestions are conservative and reviewable', () {
    expect(FamilyRelations.suggest('بابا'), 'پدر');
    expect(FamilyRelations.suggest('مادر عزیزم'), 'مادر');
    expect(FamilyRelations.suggest('برادر علی'), 'برادر');
    expect(FamilyRelations.suggest('مادربزرگ'), 'مادربزرگ');
    expect(FamilyRelations.suggest('رضا برادرزاده'), isNull);
    expect(FamilyRelations.suggest('همکار مادرزادی'), isNull);
    expect(FamilyRelations.suggest('محسن'), isNull);
  });
  test('offline suggestions extract limited non-financial tasks', () {
    final messages = [
      MessageRecord(sender: '09120000000', body: 'لطفا مدرک را بفرست', date: DateTime(2026, 11, 14)),
      MessageRecord(sender: '09120000000', body: 'رمز و شماره کارت را بفرست', date: DateTime(2026, 11, 13)),
      MessageRecord(sender: '09120000000', body: 'جلسه فردا است', date: DateTime(2026, 11, 12)),
    ];
    expect(ConversationInsights.actionItems(messages), hasLength(2));
    expect(ConversationInsights.summarize(messages), contains('مدرک'));
  });
}
