import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/message_search.dart';

void main() {
  test('large cold search yields to input and discards a cancelled scan', () async {
    final rows = List.generate(18000, (i) => MessageRecord(
      sender: 'بانک', body: 'شناسهٔ واریز $i مبلغ ۱۲٬۳۴۵ ریال',
      date: DateTime(2026), read: true,
    ));
    var cancelled = false;
    Timer.run(() => cancelled = true);
    final discarded = await MessageSearch.scan(rows, ['واریز'],
      Stopwatch()..start(), () => cancelled);
    expect(cancelled, isTrue);
    expect(discarded, isEmpty);

    final result = await MessageSearch.scan(rows, ['17999', '12345'],
      Stopwatch()..start(), () => false);
    expect(result, [rows.last]);
  });
}
