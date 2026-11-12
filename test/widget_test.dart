import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Persian inbox shows conversations and the new-message button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    expect(find.text('پیامیار'), findsOneWidget);
    expect(find.text('پیام جدید'), findsOneWidget);
    expect(find.text('هنر مردمی'), findsOneWidget);
  });
  testWidgets('Settings tab shows appearance options', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ظاهر و قالب گفتگو'));
    await tester.pumpAndSettle();
    expect(find.text('شخصی‌سازی ظاهر و فونت'), findsOneWidget);
    expect(find.text('حالت نمایش'), findsOneWidget);
  });
  testWidgets('Opening a conversation shows a one-tap code copy button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.tap(find.text('سامانه'));
    await tester.pumpAndSettle();
    expect(find.text('کپی کد ۴۸۲۱۳'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
