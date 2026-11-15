import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    expect(restored.notifyBubbles, true);
    await restored.updateNotify(bannerOpacity: .6);
    final reloaded = AppSettings();
    await reloaded.load();
    expect(reloaded.notifyBubbles, true);
    await reloaded.updateNotify(notifyBubbles: false);
    await restored.load();
    expect(restored.notifyBubbles, false);
    reloaded.dispose();
    expect(restored.bannerCompact, true);
    expect(restored.bannerMaxWidth, 340);
    settings.dispose();
    restored.dispose();
  });
}
