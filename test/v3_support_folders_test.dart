import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_settings.dart';
import 'package:payamyar/conversation_folders.dart';
import 'package:payamyar/support_service.dart';
import 'package:payamyar/text_polish.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('private support response parses without exposing phone details', () {
    final ticket = SupportTicket.fromJson({
      'id': 41, 'subject': 'اعلان', 'category': 'notification',
      'status': 'answered',
      'entries': [
        {'role': 'user', 'body': 'اعلان مشکل دارد', 'time': '2026-11-15'},
        {'role': 'admin', 'body': 'تنظیم را بررسی کنید', 'time': '2026-11-15'},
      ],
    });
    expect(ticket.id, 41);
    expect(ticket.entries.last.role, 'admin');
    expect(ticket.entries.last.body, contains('تنظیم'));
  });

  test('local folders survive reload and SMS body is not persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final folders = ConversationFolders();
    await folders.load();
    expect(await folders.create('خانواده'), isTrue);
    expect(await folders.create('خانواده'), isFalse);
    await folders.assign('0912 123 4567', 'خانواده');
    final reload = ConversationFolders();
    await reload.load();
    expect(reload.forAddress('09121234567'), 'خانواده');
    await reload.remove('خانواده');
    expect(reload.forAddress('09121234567'), isNull);
    folders.dispose();
    reload.dispose();
  });

  test('night theme observes a local overnight interval', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppSettings();
    await prefs.update(autoNight: true, nightStart: 20 * 60, nightEnd: 7 * 60);
    expect(prefs.effectiveMode(DateTime(2026, 11, 15, 22)), ThemeMode.dark);
    expect(prefs.effectiveMode(DateTime(2026, 11, 16, 8)), ThemeMode.light);
    prefs.dispose();
  });

  test('SMS compaction only removes extra space and retains wording', () {
    const before = 'سلام   وقت  بخیر\n\n\nممنون';
    final after = TextPolish.compactSms(before);
    expect(after, 'سلام وقت بخیر\n\nممنون');
    expect(after.length, lessThan(before.length));
    expect(TextPolish.compactSms(after), after);
  });
}
