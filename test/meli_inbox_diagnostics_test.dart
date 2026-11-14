import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payamyar/sms_panel/meli_payamak.dart';

void main() {
  test('GetMessages rejection never falsely claims credentials are wrong', () async {
    final client = MeliPayamak('owner', 'secret', client: MockClient((request) async {
      expect(request.url.path, '/api/SendSMS/GetMessages');
      expect(request.bodyFields['UserName'], 'owner');
      expect(request.bodyFields['PassWord'], 'secret');
      expect(request.bodyFields['Location'], '1');
      return http.Response(jsonEncode({'RetStatus': 0, 'Value': '0'}), 200);
    }));
    await expectLater(client.messages(), throwsA(isA<PanelException>()
      .having((e) => e.message, 'provider status', allOf(
        contains('GetMessages'), contains('RetStatus=0'),
        isNot(contains('نام کاربری یا رمز')), isNot(contains('secret'))))));
    client.close();
  });

  test('successful empty provider inbox is a valid result', () async {
    final client = MeliPayamak('owner', 'secret', client: MockClient((_) async =>
      http.Response(jsonEncode({'RetStatus': 1, 'Value': '[]'}), 200)));
    expect(await client.messages(), isEmpty);
    client.close();
  });
}
