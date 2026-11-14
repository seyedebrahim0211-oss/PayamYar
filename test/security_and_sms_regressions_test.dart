import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/sms_bridge.dart';
import 'package:payamyar/security/app_lock.dart';
import 'package:payamyar/security/vault.dart';
import 'package:payamyar/sms_panel/meli_payamak.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing Keystore PIN never bypasses previously enabled app lock', () async {
    SharedPreferences.setMockInitialValues({'appLock': true, 'secureScreen': true});
    await Vault.remove(AppLock.vaultName);
    final lock = AppLock();
    await lock.load();
    expect(lock.enabled, true);
    expect(lock.locked, true);
    final result = await lock.unlock('1234');
    expect(result.notSet, true);
    expect(result.ok, false);
    expect(lock.locked, true);
    lock.dispose();
  });

  test('Android non-default cannot queue an unrecorded outgoing SMS', () async {
    final store = AppStore(android: true);
    store.permissions = const SmsPermissionState(canRead: false,
      canSend: true, isDefault: false);
    String? notice;
    store.onNotice = (text) => notice = text;
    final pending = await store.send('09121234567', 'سلام');
    expect(pending, isNull);
    expect(store.pendingSends, isEmpty);
    expect(store.messages, isEmpty);
    expect(notice, contains('پیش‌فرض'));
    store.dispose();
  });

  test('bulk SMS has cancellation word LAST after signature', () {
    final text = MeliPayamak.compose('متن پیام' + String.fromCharCode(10) + 'لغو۱۱',
      bulk: true, signature: 'هنر مردمی');
    expect(text.endsWith('لغو11'), true);
    expect(text.endsWith('هنر مردمی' + String.fromCharCode(10) + 'لغو11'), true);
    expect(RegExp(r'لغو[۱١1][۱١1]$').allMatches(text).length, 1);
  });
  test('ordinary SMS does not invent cancellation marker', () {
    expect(MeliPayamak.compose('سلام', bulk: false), 'سلام');
  });
}
