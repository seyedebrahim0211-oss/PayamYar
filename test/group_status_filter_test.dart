import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/screens/group_conversation_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group recipient status filter keeps failed and sent SMS separate', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    final at = DateTime(2026, 11, 21, 12);
    const good = '09121234567';
    const bad = '09121112222';
    final group = await store.smsGroups.save('گروه آزمایش', [good, bad]);
    await store.smsGroups.recordBatch(group.id, 'اطلاعیه مشترک',
      {good: at, bad: at}, exactTime: true);
    store.ingestForTesting([
      MessageRecord(sender: good, body: 'اطلاعیه مشترک', date: at,
        outgoing: true, type: 2, id: 1),
      MessageRecord(sender: bad, body: 'اطلاعیه مشترک', date: at,
        outgoing: true, type: 5, id: 2),
    ]);
    await tester.pumpWidget(MaterialApp(home:
      GroupConversationScreen(store: store, group: group)));
    await tester.pumpAndSettle();
    expect(find.text('ناموفق'), findsOneWidget);
    await tester.tap(find.text('ناموفق'));
    await tester.pumpAndSettle();
    expect(find.text('ارسال نشد'), findsOneWidget);
    expect(find.text('ثبت‌شده در پیامک‌های گوشی'), findsNothing);
    await tester.tap(find.text('ثبت‌شده').last);
    await tester.pumpAndSettle();
    expect(find.text('ارسال نشد'), findsNothing);
    expect(find.text('ثبت‌شده در پیامک‌های گوشی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
