import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/screens/group_conversation_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('group shows the exact sent SMS under a saved contact name', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppStore(android: false);
    const to = '09121234567';
    final at = DateTime(2026, 11, 14, 11);
    final group = await app.smsGroups.save('همکاران', [to, '09123334444']);
    await app.smsGroups.recordBatch(group.id, 'سلام به اعضای گروه', {to: at});
    app.names[to] = 'محمد رضایی';
    app.ingestForTesting([
      MessageRecord(sender: to, body: 'سلام به اعضای گروه',
        date: at.add(const Duration(seconds: 6)), outgoing: true, type: 2, id: 11),
      MessageRecord(sender: to, body: 'پیام شخصی نامرتبط',
        date: at.subtract(const Duration(days: 7)), outgoing: true, type: 2, id: 12),
    ]);
    await tester.pumpWidget(MaterialApp(home: GroupConversationScreen(store: app, group: group)));
    await tester.pumpAndSettle();
    expect(find.text('محمد رضایی'), findsOneWidget);
    expect(find.text('سلام به اعضای گروه'), findsOneWidget);
    expect(find.text('پیام شخصی نامرتبط'), findsNothing);
    expect(find.text('ثبت‌شده در پیامک‌های گوشی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
