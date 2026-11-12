import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_settings.dart';
import 'package:payamyar/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signature is appended once and only when enabled', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    expect(s.withSignature(' سلام '), 'سلام');
    await s.update(signature: 'با احترام', signatureEnabled: true);
    expect(s.withSignature('سلام'), 'سلام\nبا احترام');
    expect(s.withSignature('سلام\nبا احترام'), 'سلام\nبا احترام');
  });

  test('send delay respects the switch and the 1..10 second range', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.update(sendDelaySeconds: 30);
    expect(s.sendDelay, const Duration(seconds: 10));
    await s.update(sendDelayEnabled: false);
    expect(s.sendDelay, Duration.zero);
  });

  test('settings persist and reload', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.update(chatStyle: ChatStyle.glass, sentFeedback: SentFeedback.silent, quietHours: true);
    final again = AppSettings();
    await again.load();
    expect(again.chatStyle, ChatStyle.glass);
    expect(again.sentFeedback, SentFeedback.silent);
    expect(again.quietHours, isTrue);
  });

  test('backup round-trips settings and templates, rejects foreign text', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    final store = AppStore();
    await store.init();
    store.templates.add('در جلسه هستم');
    await s.update(chatStyle: ChatStyle.minimal, sendDelaySeconds: 3);
    final text = store.exportBackup(s);

    SharedPreferences.setMockInitialValues({});
    final s2 = AppSettings();
    final store2 = AppStore();
    await store2.init();
    expect(await store2.importBackup('hello', s2), isFalse);
    expect(await store2.importBackup(text, s2), isTrue);
    expect(s2.chatStyle, ChatStyle.minimal);
    expect(s2.sendDelaySeconds, 3);
    expect(store2.templates, contains('در جلسه هستم'));
  });
}
