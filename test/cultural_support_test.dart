import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/screens/support_pages.dart';

void main() {
  testWidgets('cultural support is optional and opens the official site', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: CulturalSupportPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('نذر فرهنگی پیام‌یار'), findsOneWidget);
    expect(find.textContaining('کاملاً اختیاری'), findsOneWidget);
    expect(find.byKey(const ValueKey('cultural-support-donate')), findsOneWidget);
    expect(CulturalSupportPage.supportUrl,
      'https://honarmardomi.ir/payamyar-cultural-support/');
    expect(tester.takeException(), isNull);
  });
}
