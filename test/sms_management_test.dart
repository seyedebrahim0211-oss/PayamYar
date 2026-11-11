import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/main.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/conversation_logic.dart';

void main() {
  test('Conversation retains provider identities and unread state across Iranian number aliases', () {
    final rows = [
      MessageRecord(id: 41, sender: '+989121234567', body: 'old', date: DateTime(2026), read: false),
      MessageRecord(id: 42, sender: '۰۹۱۲۱۲۳۴۵۶۷', body: 'reply', date: DateTime(2026, 2), outgoing: true, type: 5),
    ];
    final group = ConversationLogic.group(rows).single;
    expect(group.count, 2);
    expect(group.latest.id, 42);
    expect(group.latest.type, 5);
    expect(group.messages.any((m) => !m.read), isTrue);
  });
  testWidgets('Saved draft survives reopening the composer and exposes SMS length limit', (tester) async {
    SharedPreferences.setMockInitialValues({'draft_to': '09121234567', 'draft_body': 'پیش‌نویس من'});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.tap(find.text('پیام جدید'));
    await tester.pumpAndSettle();
    expect(find.text('پیش‌نویس من'), findsOneWidget);
    expect(find.text('09121234567'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.any((f) => f.maxLength == 2000), isTrue);
  });
}
