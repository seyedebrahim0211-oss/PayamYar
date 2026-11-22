import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/screens/failed_messages_screen.dart';
import 'package:payamyar/screens/group_inbox_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed count updates when messages are added or removed', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    final now = DateTime(2026, 11, 21);
    store.ingestForTesting([
      MessageRecord(sender: '09121234567', body: 'اول', date: now,
          type: 5, outgoing: true, id: 1),
      MessageRecord(sender: '09121234568', body: 'دوم', date: now,
          type: 2, delivery: 64, outgoing: true, id: 2),
      MessageRecord(sender: '09121234569', body: 'سوم', date: now,
          type: 2, outgoing: true, id: 3),
    ]);
    expect(store.failedMessagesCount, 2);
    await store.deleteMessages([1]);
    expect(store.failedMessagesCount, 1);
    store.dispose();
  });

  testWidgets('failed inbox selects and deletes only failed SMS', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    final now = DateTime(2026, 11, 21);
    store.ingestForTesting([
      MessageRecord(sender: '09121234567', body: 'متن ناموفق', date: now,
          type: 5, outgoing: true, id: 41),
      MessageRecord(sender: '09121234568', body: 'متن تحویل‌ناموفق', date: now,
          type: 2, delivery: 64, outgoing: true, id: 42),
      MessageRecord(sender: '09121234569', body: 'پیام موفق', date: now,
          type: 2, outgoing: true, id: 43),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: FailedMessagesScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('متن ناموفق'), findsOneWidget);
    expect(find.text('متن تحویل‌ناموفق'), findsOneWidget);
    expect(find.text('پیام موفق'), findsNothing);
    await tester.tap(find.text('انتخاب همه'));
    await tester.pump();
    await tester.tap(find.text('حذف انتخابی'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف انتخاب‌شده‌ها'));
    await tester.pumpAndSettle();
    expect(store.messages.map((m) => m.id), [43]);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('group-specific retry inbox never includes failures from other groups',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    final at = DateTime(2026, 11, 22);
    store.ingestForTesting([
      MessageRecord(sender: '09120000001', body: 'فقط عضو این گروه',
        date: at, outgoing: true, type: 5, id: 101),
      MessageRecord(sender: '09120000002', body: 'ناموفق گروه دیگر',
        date: at, outgoing: true, type: 5, id: 102),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: FailedMessagesScreen(store: store, restrictedIds: {101})));
    await tester.pumpAndSettle();
    expect(find.text('فقط عضو این گروه'), findsOneWidget);
    expect(find.text('ناموفق گروه دیگر'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('group item in inbox expands and opens its real group view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    await store.smsGroups.save('گروه محله',
        ['09121234567', '09121110000']);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GroupInboxSection(store: store))));
    await tester.pumpAndSettle();
    expect(find.text('پیام‌های گروهی'), findsOneWidget);
    await tester.tap(find.text('پیام‌های گروهی'));
    await tester.pumpAndSettle();
    expect(find.text('گروه محله'), findsOneWidget);
    await tester.tap(find.text('گروه محله'));
    await tester.pumpAndSettle();
    expect(find.text('ارسال‌های گروه'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  test('failed group retry matches only exact original broadcast', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    final group = await store.smsGroups.save('همکاران',
        ['09121234567', '09123334444']);
    final when = DateTime(2026, 11, 21, 10);
    await store.smsGroups.recordBatch(group.id, 'پیام اولیه',
        {'09121234567': when}, exactTime: true);
    expect(await store.smsGroups.matchingFailedBatch(
      recipient: '09121234567', body: 'پیام دیگر',
      messageDate: when), isNull);
    await store.smsGroups.recordRetryForFailed(
      recipient: '09121234567', originalBody: 'پیام اولیه',
      originalDate: when, newBody: 'پیام اصلاح‌شده',
      queuedAt: when.add(const Duration(seconds: 20)));
    expect(store.smsGroups.batchesFor(group.id).length, 2);
    await store.smsGroups.removeFailedFromHistory(
      recipient: '09121234567', body: 'پیام اولیه',
      messageDate: when);
    expect(store.smsGroups.batchesFor(group.id).length, 1);
    store.dispose();
  });
}
