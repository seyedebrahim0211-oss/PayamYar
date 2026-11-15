import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/csv_util.dart';

void main() {
  test('formula prefixes cannot hide behind whitespace or phone punctuation', () {
    for (final input in ['+10-20-30', '-1+2', '  =SUM(A1)', '\t@SUM(A1)',
      '\r=1+1', '\n=1+1', '\uFEFF=1+1', '+(123)456']) {
      expect(csvCell(input), startsWith('"\''), reason: input);
    }
    expect(csvCell('+989121234567'), '"+989121234567"');
    expect(csvCell('علی'), '"علی"');
  });
  test('Persian Excel export retains UTF-8 BOM and quote escaping', () {
    final bytes = csvBytes([['نام', 'علی "رضا"']]);
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(bytes), contains('"علی ""رضا"""'));
  });
}
