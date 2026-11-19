import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/notify_banner.dart';
import 'package:payamyar/screens/glass_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy vivid notification preferences migrate to one readable glass design', () async {
    SharedPreferences.setMockInitialValues({
      'bannerStyle': BannerStyle.vivid.index,
      'bannerCompact': true,
      'notifyBubbles': true,
      'bannerOpacity': .22,
    });
    final s = AppSettings();
    await s.load();
    expect(s.bannerStyle, BannerStyle.glass);
    expect(s.bannerCompact, isFalse);
    expect(s.notifyBubbles, isFalse);
    expect(s.bannerOpacity, greaterThanOrEqualTo(.78));
  });

  test('personalized glass controls persist across app restart', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.updateNotify(
      bannerSourceColors: false,
      bannerSenderTints: {'EITAA': 0xffa05326},
      bannerHue: 205,
      bannerEdge: .85,
      bannerShine: .7,
      bannerCorner: 32,
      bannerOpacity: .93,
      bannerStyle: BannerStyle.vivid,
      bannerCompact: true,
      notifyBubbles: true,
      bannerActionSize: BannerActionSize.large,
      bannerActionIcons: false,
      bannerActionCode: true,
      notifyOpen: false, notifyDismiss: false, notifyCall: false, notifyMarkRead: false,
    );
    final next = AppSettings();
    await next.load();
    expect(next.bannerStyle, BannerStyle.glass);
    expect(next.bannerCompact, isFalse);
    expect(next.notifyBubbles, isFalse);
    expect(next.bannerSourceColors, isFalse);
    expect(next.bannerSenderTints['EITAA'], 0xffa05326);
    expect(next.bannerHue, 205);
    expect(next.bannerEdge, .85);
    expect(next.bannerShine, .7);
    expect(next.bannerCorner, 32);
    expect(next.bannerOpacity, .93);
    expect(next.bannerActionSize, BannerActionSize.large);
    expect(next.bannerActionIcons, isFalse);
    expect(next.bannerActionCode, isTrue);
    expect([next.notifyOpen, next.notifyDismiss, next.notifyCall, next.notifyMarkRead], everyElement(isFalse));
    final restored = AppSettings();
    await restored.restore(next.toJson());
    expect(restored.notifyJson(), next.notifyJson());
  });
  testWidgets('compact OTP is actionable and reply controls appear on demand', (tester) async {
    final settings = AppSettings()..reduceEffects = true;
    final banner = IncomingBanner.preview();
    String? copied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 300,
              child: GlassBannerCard(settings: settings, banner: banner, onCopy: (code) => copied = code),
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text(banner.body)).maxLines, 2);
    expect(find.text('پاسخ'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    final copy = find.text('کپی کد');
    final button = find.ancestor(of: copy, matching: find.byType(TextButton));
    final face = find.descendant(of: button, matching: find.byType(Material));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(face).height, lessThan(36));
    await tester.tap(copy);
    expect(copied, '12345');
    await tester.tap(find.byTooltip('نمایش متن کامل'));
    await tester.pump();
    expect(find.text(banner.body), findsOneWidget);
    expect(tester.widget<Text>(find.text(banner.body)).maxLines, isNull);
    await tester.tap(find.text('پاسخ'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an eight-digit OTP stays intact or uses the short label as space changes', (tester) async {
    final settings = AppSettings()..bannerActionCode = true;
    final banner = IncomingBanner(address: 'test', name: 'بانک', body: 'کد ورود', time: DateTime(2026), otp: '12345678');
    String? copied;
    Future<void> layout(double width, double scale) async {
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), textScaler: TextScaler.linear(scale)),
        child: Align(child: SizedBox(width: width, child: GlassBannerCard(
          banner: banner, settings: settings, onCopy: (value) => copied = value))),
      )));
    }
    await layout(360, 1);
    expect(find.text('کپی کد ۱۲۳۴۵۶۷۸'), findsOneWidget);
    settings.bannerActionSize = BannerActionSize.large;
    settings.bannerActionIcons = false;
    await layout(200, 2);
    final compact = find.text('کپی کد');
    expect(tester.widget<Text>(compact).maxLines, 1);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    await tester.tap(compact);
    expect(copied, '12345678');
    expect(tester.takeException(), isNull);
  });

  testWidgets('large type and long text fit a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(260, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings();
    final banner = IncomingBanner(
      address: '1234',
      name: 'پیام‌یار',
      time: DateTime(2026),
      body: List.filled(80, 'یک پیام بلند برای بررسی خوانایی').join(' '),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(260, 320), textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SizedBox(
              width: 260,
              child: GlassBannerCard(settings: settings, banner: banner),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('نمایش متن کامل'));
    await tester.pumpAndSettle();
    expect(find.text(banner.body), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
