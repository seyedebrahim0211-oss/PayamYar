import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/screens/compose_screen.dart';
import 'package:payamyar/screens/group_conversation_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved group shows historical member SMS as private, not group broadcast', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    const number = '09121234567';
    final group = await store.smsGroups.save('گروه آزمایشی', [number, '09123334444']);
    store.names[number] = 'مخاطب نمونه';
    store.ingestForTesting([
      MessageRecord(sender: number, body: 'پیام خصوصی قدیمی',
        date: DateTime(2026, 11, 14, 10), outgoing: true, type: 2, id: 11),
    ]);
    await tester.pumpWidget(MaterialApp(home: GroupConversationScreen(store: store, group: group)));
    await tester.pumpAndSettle();
    expect(find.text('پیام خصوصی قدیمی'), findsOneWidget);
    expect(find.text('پیام خصوصی ارسالی'), findsOneWidget);
    expect(find.text('پیام‌های اعضا'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('sending from a saved group never allows recipient editing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    final group = await store.smsGroups.save('گروه امن', ['09121234567', '09123334444']);
    await tester.pumpWidget(MaterialApp(home: ComposeScreen(
      store: store, initialRecipients: group.recipients, initialGroupName: group.name,
      initialGroupId: group.id, createGroup: true, lockGroupRecipients: true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('گیرندگان این ارسال فقط اعضای ذخیره‌شده گروه هستند'), findsOneWidget);
    expect(find.text('نام یا شماره گیرنده'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
