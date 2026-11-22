import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/screens/message_collection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('advanced search starts without keyboard and filters local messages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    final now = DateTime(2026, 11, 22);
    store.ingestForTesting([
      MessageRecord(sender: '09121112222', body: 'پیام ساده', date: now, id: 1),
      MessageRecord(sender: '09123334444', body: 'پیوند https://example.org',
        date: now, id: 2),
    ]);
    await tester.pumpWidget(MaterialApp(home:
      MessageCollection(store: store, kind: CollectionKind.search)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('پیام ساده'), findsOneWidget);
    expect(find.textContaining('تعداد نتایج'), findsOneWidget);

    await tester.tap(find.text('لینک‌دار'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('پیام ساده'), findsNothing);
    expect(find.text('پیوند https://example.org'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
