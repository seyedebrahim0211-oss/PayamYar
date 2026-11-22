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
    expect(find.text('نذر فرهنگی'), findsOneWidget);
    // The voluntary-payment notice and button are below the fold on small
    // screens. Scroll as a person would instead of assuming eager list layout.
    await tester.scrollUntilVisible(find.textContaining('کاملاً اختیاری'), 180);
    expect(find.textContaining('کاملاً اختیاری'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('cultural-support-donate')), 180);
    expect(find.byKey(const ValueKey('cultural-support-donate')), findsOneWidget);
    expect(CulturalSupportPage.supportUrl,
      'https://honarmardomi.ir/nazr-farhangi/');
    expect(tester.takeException(), isNull);
  });
}
