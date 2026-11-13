import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payamyar/csv_util.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/report_logic.dart';
import 'package:payamyar/security/vault.dart';
import 'package:payamyar/sms_panel/meli_payamak.dart';

void main() {
  group('Meli Payamak client', () {
    MeliPayamak client(Object Function(http.Request r) reply) => MeliPayamak('user', 'key',
        client: MockClient((r) async => http.Response(jsonEncode(reply(r)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})));

    test('reads credit over HTTPS form post with credentials', () async {
      late http.Request seen;
      final api = client((r) {
        seen = r;
        return {'Value': '1250.5', 'RetStatus': 1, 'StrRetStatus': 'Ok'};
      });
      expect(await api.credit(), 1250.5);
      expect(seen.url.toString(), 'https://rest.payamak-panel.com/api/SendSMS/GetCredit');
      expect(seen.bodyFields['username'], 'user');
      expect(seen.bodyFields['password'], 'key');
    });

    test('maps error codes to Persian messages', () async {
      final api = client((_) => {'Value': '2', 'RetStatus': 0, 'StrRetStatus': 'InvalidData'});
      expect(() => api.send(to: ['09121234567'], text: 'سلام'),
          throwsA(isA<PanelException>().having((e) => e.message, 'message', contains('اعتبار'))));
    });

    test('sends to normalised numbers from line 90008325', () async {
      late http.Request seen;
      final api = client((r) {
        seen = r;
        return {'Value': '4521369874521', 'RetStatus': 1, 'StrRetStatus': 'Ok'};
      });
      final id = await api.send(to: ['۰۹۱۲ ۱۲۳ ۴۵۶۷', '+989351112233', 'bad'], text: 'تست');
      expect(id, '4521369874521');
      expect(seen.bodyFields['to'], '09121234567,09351112233');
      expect(seen.bodyFields['from'], MeliPayamak.defaultLine);
    });

    test('parses received messages from Data', () async {
      final api = client((r) {
        expect(r.bodyFields['location'], '1');
        return {
          'Value': '', 'RetStatus': 1, 'StrRetStatus': 'Ok',
          'Data': [
            {'MsgID': 11, 'Body': 'قدیمی', 'Sender': '09121111111', 'Receiver': '90008325', 'SendDate': '2026-11-01T10:00:00'},
            {'MsgID': 12, 'Body': 'جدید', 'Sender': '09122222222', 'Receiver': '90008325', 'SendDate': '/Date(1794000000000)/'},
          ],
        };
      });
      final list = await api.messages();
      expect(list.length, 2);
      expect(list.first.body, 'جدید');
      expect(list.last.receiver, '90008325');
    });

    test('normalize keeps only valid Iranian mobiles', () {
      expect(MeliPayamak.normalize('00989121234567'), '09121234567');
      expect(MeliPayamak.normalize('9121234567'), '09121234567');
      expect(MeliPayamak.normalize('12345'), '');
    });
  });

  test('CSV export neutralises spreadsheet formulas but keeps phone numbers', () {
    expect(csvCell('=HYPERLINK("http://x")'), '"\'=HYPERLINK(""http://x"")"');
    expect(csvCell('@SUM(A1)'), '"\'@SUM(A1)"');
    expect(csvCell('+989121234567'), '"+989121234567"');
    expect(csvCell('علی'), '"علی"');
  });

  group('phishing detection', () {
    test('flags fake judicial notice with look-alike domain', () {
      final r = MessageLogic.risk('ابلاغیه الکترونیک برای شما صادر شد. مشاهده: https://adliran-sabt.xyz/p');
      expect(r.suspicious, isTrue);
      expect(r.reasons.join(), contains('جعلی'));
    });
    test('flags shortened links with lure words', () {
      expect(MessageLogic.suspicious('یارانه شما واریز نشد، ثبت نام: bit.ly/abc'), isTrue);
    });
    test('does not flag official bank site or plain amounts', () {
      expect(MessageLogic.suspicious('برای جلوگیری از مسدود شدن کارت به www.bmi.ir مراجعه کنید'), isFalse);
      expect(MessageLogic.suspicious('برداشت 1.500.000 ریال'), isFalse);
    });
  });

  test('report compares periods and builds insights', () {
    final now = DateTime(2026, 11, 13, 12);
    final msgs = <MessageRecord>[
      for (var i = 0; i < 12; i++)
        MessageRecord(sender: '09121234567', body: 'سلام دوست عزیز', date: now.subtract(Duration(days: i % 6))),
      for (var i = 0; i < 4; i++)
        MessageRecord(sender: '09121234567', body: 'سلام', date: now.subtract(Duration(days: 35 + i))),
      MessageRecord(sender: 'بانک ملت', body: 'برداشت 2,000,000 ریال موجودی 5,000,000 ریال', date: now.subtract(const Duration(days: 2))),
    ];
    final r = buildReportAt(msgs, now);
    final month = r.periods[ReportPeriod.month]!;
    expect(month.received, 13);
    expect(month.prevReceived, 4);
    expect(month.withdrawals, 200000);
    expect(month.trendIn.length, 30);
    expect(month.trendIn.fold<int>(0, (a, b) => a + b), 13);
    final insights = buildInsights(month, ReportPeriod.month);
    expect(insights.any((i) => i.text.contains('بیشتر')), isTrue);
    final text = reportAsText(r, month, ReportPeriod.month, nameOf: (k) => k, money: (v) => '$v');
    expect(text, contains('گزارش پیامیار'));
    expect(transactionsAsRows(month.transactions).length, 2);
  });

  test('PIN check results are explained in Persian', () async {
    expect(PinCheck.parse('ok').ok, isTrue);
    expect(PinCheck.parse('wrong:3').message, contains('3'));
    expect(PinCheck.parse('locked:120').message, contains('2 دقیقه'));
    await Vault.setPin('t', '123456');
    expect((await Vault.verifyPin('t', '123456')).ok, isTrue);
    expect((await Vault.verifyPin('t', '000000')).ok, isFalse);
  });
}
