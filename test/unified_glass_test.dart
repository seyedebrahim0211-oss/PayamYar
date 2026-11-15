import 'package:flutter_test/flutter_test.dart';
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
    await s.updateNotify(bannerHue: 205, bannerEdge: .85,
      bannerShine: .7, bannerCorner: 32, bannerOpacity: .93,
      bannerStyle: BannerStyle.vivid, bannerCompact: true, notifyBubbles: true);
    final next = AppSettings();
    await next.load();
    expect(next.bannerStyle, BannerStyle.glass);
    expect(next.bannerCompact, isFalse);
    expect(next.notifyBubbles, isFalse);
    expect(next.bannerHue, 205);
    expect(next.bannerEdge, .85);
    expect(next.bannerShine, .7);
    expect(next.bannerCorner, 32);
    expect(next.bannerOpacity, .93);
  });
}
