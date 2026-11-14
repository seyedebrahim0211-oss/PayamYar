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
      bannerMaxWidth: 340);
    expect(settings.bannerTop, false);
    final restored = AppSettings();
    await restored.load();
    expect(restored.bannerTop, false);
    expect(restored.bannerCompact, true);
    expect(restored.bannerMaxWidth, 340);
    settings.dispose();
    restored.dispose();
  });
}
