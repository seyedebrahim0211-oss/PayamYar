import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/sms_groups.dart';
import 'package:payamyar/security/vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('broadcast history records only queued recipients and encrypts message body', () async {
    SharedPreferences.setMockInitialValues({});
    final groups = SmsGroupStore();
    final group = await groups.save('همکاران', ['09121234567', '09123334444']);
    final at = DateTime(2026, 11, 14, 10, 30);
    await groups.recordBatch(group.id, 'سلام اعضای گروه', {'09121234567': at});
    final records = groups.batchesFor(group.id);
    expect(records.length, 1);
    expect(records.single.acceptedAt.length, 1);
    expect(records.single.acceptedAt.keys.single, SmsGroupStore.normalize('09121234567'));
    expect(await groups.batchBody(records.single), 'سلام اعضای گروه');
    final pref = await SharedPreferences.getInstance();
    final metadata = pref.getStringList(SmsGroupStore.batchKey)?.join('') ?? '';
    expect(metadata, isNot(contains('سلام اعضای گروه')));
    final restored = SmsGroupStore();
    await restored.load();
    expect(restored.batchesFor(group.id).length, 1);
    expect(await restored.batchBody(restored.batchesFor(group.id).single), 'سلام اعضای گروه');
    await restored.remove(group.id);
    expect(await Vault.get(records.single.vaultKey), isNull);
    groups.dispose();
    restored.dispose();
  });

  test('bad recipients are deduplicated and normalized', () {
    final result = SmsGroupStore.uniqueRecipients(['09121234567', '+989121234567', 'bad']);
    expect(result.length, 1);
  });
}
