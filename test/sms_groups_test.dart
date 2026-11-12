import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/sms_groups.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('local SMS broadcast group can be created, loaded and removed', () async {
    SharedPreferences.setMockInitialValues({});
    final groups = SmsGroupStore();
    await groups.load();
    expect(groups.groups, isEmpty);
    final created = await groups.save('همکاران', [
      '+989121234567', '09121234567', '09129876543',
    ]);
    expect(created.recipients, hasLength(2));
    expect(created.recipients.first, '09121234567');
    expect(groups.groups.single.name, 'همکاران');

    final restored = SmsGroupStore();
    await restored.load();
    expect(restored.groups.single.id, created.id);
    expect(restored.groups.single.recipients, hasLength(2));
    await restored.remove(created.id);
    expect(restored.groups, isEmpty);
    groups.dispose();
    restored.dispose();
  });

  test('group names and recipient size are validated', () async {
    SharedPreferences.setMockInitialValues({});
    final groups = SmsGroupStore();
    await expectLater(groups.save('', ['09121234567', '09120000000']), throwsArgumentError);
    await expectLater(groups.save('گروه بدون اعضا', ['09121234567']), throwsArgumentError);
    final many = List.generate(501, (i) => '0912' + i.toString().padLeft(7, '0'));
    await expectLater(groups.save('گروه بزرگ', many), throwsArgumentError);
    groups.dispose();
  });

  test('broadcast is private: only member list is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SmsGroupStore();
    await store.save('دوستان', ['09121234567', '09120000000']);
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList(SmsGroupStore.storageKey)!;
    expect(saved.single, contains('دوستان'));
    expect(saved.single, isNot(contains('پیام ارسال شده')));
    store.dispose();
  });
}
