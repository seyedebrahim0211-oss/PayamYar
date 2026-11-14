import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payamyar/sms_panel/meli_payamak.dart';

void main() {
  test('panel requests go to the official HTTPS API with form credentials', () async {
    final api = MeliPayamak('owner', 'api-secret', client: MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, MeliPayamak.host);
      expect(request.url.path, '/api/SendSMS/GetCredit');
      expect(request.bodyFields['username'], 'owner');
      expect(request.bodyFields['password'], 'api-secret');
      return http.Response(jsonEncode({'RetStatus': 1, 'Value': '57'}), 200);
    }));
    expect(await api.credit(), 57);
    api.close();
  });

  test('number validation accepts Iranian mobile formats only', () {
    expect(MeliPayamak.normalize('۰۹۱۲ ۱۲۳ ۴۵۶۷'), '09121234567');
    expect(MeliPayamak.normalize('+98 912 123 4567'), '09121234567');
    expect(MeliPayamak.normalize('90008325'), '');
    expect(MeliPayamak.normalize('02112345678'), '');
  });

  test('received panel record decoding preserves receiver and content', () {
    final message = PanelMessage.fromJson({
      'MsgID': 10, 'Sender': '09121234567', 'Receiver': '90008325',
      'Body': 'سلام', 'SendDate': '2026-11-13T10:30:00Z'
    });
    expect(message, isNotNull);
    expect(message!.receiver, '90008325');
    expect(message.body, 'سلام');
    expect(message.date, isNotNull);
  });

  test('API errors do not include the secret in displayed text', () async {
    final api = MeliPayamak('owner', 'very-private-key', client: MockClient((_) async =>
        http.Response(jsonEncode({'RetStatus': 0, 'Value': '0'}), 200)));
    await expectLater(api.credit(), throwsA(isA<PanelException>()
      .having((e) => e.message, 'safe error', isNot(contains('very-private-key')))));
    api.close();
  });
}
