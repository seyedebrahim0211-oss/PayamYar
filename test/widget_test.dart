import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Persian inbox and primary action are visible', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    expect(find.text('پیامیار'), findsOneWidget);
    expect(find.text('گفتگوها'), findsOneWidget);
    expect(find.text('پیام جدید'), findsOneWidget);
    expect(find.textContaining('نسخه نمایشی'), findsWidgets);
  });

  testWidgets('Appearance screen is reachable in one tap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تنظیمات ظاهر'));
    await tester.pumpAndSettle();
    expect(find.text('شخصی‌سازی'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });
}
