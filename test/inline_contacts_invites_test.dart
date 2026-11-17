import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/screens/invite_friends_screen.dart';
import 'package:payamyar/screens/message_interactions.dart';

void main() {
  testWidgets('phone number in an SMS opens action card without sending', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(
        child: InteractiveMessageText(text: 'شماره: 09916010265'),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('09916010265'), findsOneWidget);
    await tester.tap(find.text('09916010265'));
    await tester.pumpAndSettle();
    expect(find.text('تماس'), findsOneWidget);
    expect(find.text('اطلاعات'), findsOneWidget);
    expect(find.text('کپی شماره'), findsOneWidget);
    // Tapping the number only opens the card, never places a call or SMS.
  });

  testWidgets('known contact card displays a name and the original number', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => showPhoneActions(
          context, '09916010265', displayName: 'سعیدرضا'),
        child: const Text('نمایش کارت'),
      )),
    )));
    await tester.tap(find.text('نمایش کارت'));
    await tester.pumpAndSettle();
    expect(find.text('سعیدرضا'), findsOneWidget);
    expect(find.text('09916010265'), findsOneWidget);
    expect(find.text('پیام'), findsOneWidget);
  });

  testWidgets('invite friends page offers voluntary SMS and share actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: InviteFriendsScreen(store: AppStore(android: false)),
    ));
    expect(find.text('معرفی به دوستان'), findsOneWidget);
    expect(find.text('دعوت با پیامک'), findsOneWidget);
    expect(find.text('اشتراک‌گذاری در برنامه‌های دیگر'), findsOneWidget);
    expect(find.text('کپی لینک دانلود'), findsOneWidget);
  });
}
