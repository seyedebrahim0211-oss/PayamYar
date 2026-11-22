import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/screens/carrier_sms_limits.dart';

void main() {
  testWidgets('MCI quota guide is qualified and readable', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CarrierSmsLimits()))));
    expect(find.text('راهنمای سقف پیامک همراه اول (۲۴ ساعت)'), findsOneWidget);
    expect(find.text('اعتباری: ۵۰۰ پیامک'), findsOneWidget);
    expect(find.text('دائمی: ۱٬۰۰۰ پیامک'), findsOneWidget);
    expect(find.textContaining('نه سهمیه تأییدشده'), findsOneWidget);
    expect(find.textContaining('پیامک چندبخشی'), findsOneWidget);
  });
}
