import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('left and right read gestures persist independently after upgrading', () async {
    SharedPreferences.setMockInitialValues({'swipeRightRead': false});
    final settings = AppSettings();
    await settings.load();
    expect(settings.swipeLeftRead, isFalse);
    await settings.updateNotify(swipeLeftRead: true);
    final restored = AppSettings();
    await restored.load();
    expect(restored.swipeRightRead, isFalse);
    expect(restored.swipeLeftRead, isTrue);
    settings.dispose();
    restored.dispose();
  });
  test('glass banner location persists across settings reload', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    await settings.load();
    await settings.updateNotify(bannerTop: false, bannerCompact: true,
      bannerMaxWidth: 340, notifyBubbles: true);
    expect(settings.bannerTop, false);
    final restored = AppSettings();
    await restored.load();
    expect(restored.bannerTop, false);
    expect(restored.notifyBubbles, false);
    await restored.updateNotify(bannerOpacity: .6);
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.notifyBubbles, false);
    await reloaded.updateNotify(notifyBubbles: false);
    await restored.load();
    expect(restored.notifyBubbles, false);
    reloaded.dispose();
    expect(restored.bannerCompact, false);
    expect(restored.bannerMaxWidth, 340);
    settings.dispose();
    restored.dispose();
  });
}
