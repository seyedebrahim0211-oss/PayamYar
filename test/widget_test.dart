import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PayamYar launches with Persian navigation and demo notice', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();

    expect(find.text('پیامیار'), findsWidgets);
    expect(find.text('مدیریت پیام‌ها'), findsOneWidget);
    expect(find.text('نسخه آزمایشی'), findsOneWidget);
  });

  testWidgets('User can reach appearance settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();

    final target = find.text('شخصی‌سازی').evaluate().isNotEmpty
        ? find.text('شخصی‌سازی').first
        : find.text('ظاهر').first;
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('حالت نمایش'), findsOneWidget);
  });
}
