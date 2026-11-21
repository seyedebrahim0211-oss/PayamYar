import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/screens/group_conversation_screen.dart';
import 'package:payamyar/screens/message_interactions.dart';
import 'package:payamyar/security/app_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('PIN submits once on the final digit', (tester) async {
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PinScreen(
          title: '',
          subtitle: '',
          autoLength: 6,
          onSubmit: (pin) async {
            submitted.add(pin);
            return null;
          },
        ),
      ),
    );
    for (final digit in ['۱', '۲', '۳', '۴', '۵']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(submitted, isEmpty);
    await tester.tap(find.text('۶'));
    await tester.pump();
    expect(submitted, ['123456']);
  });

  testWidgets('one tap copies complete card and IBAN with normalized digits', (
    tester,
  ) async {
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const card = '۶۰۳۷-۹۹۱۱-۲۲۲۲-۳۳۳۳';
    const iban = 'IR۱۲۳۴۵۶۷۸۹۰۱۲۳۴۵۶۷۸۹۰۱۲۳۴';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InteractiveMessageText(text: 'کارت $card و شبا $iban'),
        ),
      ),
    );
    await tester.tap(find.text(card));
    await tester.pump();
    await tester.tap(find.text(iban));
    await tester.pumpAndSettle();
    expect(copied, ['6037991122223333', 'IR123456789012345678901234']);
  });

  testWidgets('tap a failed group SMS then retry only that member', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(android: false);
    const to = '09121234567';
    final group = await store.smsGroups.save('گروه', [to, '09121110000']);
    final at = DateTime(2026, 11, 20);
    await store.smsGroups.recordBatch(group.id, 'سلام', {
      to: at,
    }, exactTime: true);
    store.ingestForTesting([
      MessageRecord(
        sender: to,
        body: 'سلام',
        date: at,
        outgoing: true,
        type: 5,
        delivery: 64,
        id: 42,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: GroupConversationScreen(store: store, group: group),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ارسال نشد'));
    await tester.pumpAndSettle();
    expect(find.text('پاک کردن'), findsOneWidget);
    await tester.tap(find.text('ارسال مجدد'));
    await tester.pumpAndSettle();
    expect(store.messages.map((m) => m.sender), [to, to]);
    expect(store.messages.first.body, 'سلام');
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
