import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/recipient_suggestions.dart';
import 'package:payamyar/sms_panel/meli_payamak.dart';

void main() {
  test('prioritize frequent outgoing SMS contacts without reading message content', () {
    final now = DateTime(2026, 11, 14);
    final scores = RecipientSuggestions.frequency([
      MessageRecord(sender: '+989121234567', body: 'x', date: now, outgoing: true),
      MessageRecord(sender: '09121234567', body: 'x', date: now, outgoing: true),
      MessageRecord(sender: '09121112222', body: 'x', date: now, outgoing: true),
      MessageRecord(sender: '09123334444', body: 'x', date: now),
    ]);
    const contacts = [
      {'name': 'پدر', 'number': '09121112222'},
      {'name': 'مادر', 'number': '09121234567'},
    ];
    expect(RecipientSuggestions.rank(contacts, scores, '').first['name'], 'مادر');
    expect(RecipientSuggestions.rank(contacts, scores, '۱۱۱۲').length, 1);
    expect(RecipientSuggestions.rank(contacts, scores, 'ماد').first['name'], 'مادر');
    expect(RecipientSuggestions.rank(contacts, scores, '', excluded: {'09121234567'}).single['name'], 'پدر');
  });
  test('accepted requests must not show failure simply because receipt ID is absent', () {
    expect(MeliPayamak.receiptFromResponse({'RetStatus': 1, 'Value': '123'}), '123');
    expect(MeliPayamak.receiptFromResponse({'RetStatus': 1, 'Value': ''}), '');
    expect(MeliPayamak.receiptFromResponse({'RetStatus': '1', 'Value': null}), '');
    expect(() => MeliPayamak.receiptFromResponse({'RetStatus': 0, 'Value': '2'}), throwsA(isA<PanelException>()));
  });
}
