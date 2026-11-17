import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/message_logic.dart';
import 'package:payamyar/report_logic.dart';

void main() {
  test('report does not mislabel failed or queued SMS as sent', () {
    final now = DateTime(2026, 11, 17, 14);
    MessageRecord message(int id, int type, {int delivery = 32}) =>
        MessageRecord(sender: '+989121234567', body: 'پیام آزمایشی', date: now.subtract(const Duration(hours: 1)),
          outgoing: true, read: true, id: id, type: type, delivery: delivery);
    final result = buildReportAt([
      message(1, 2, delivery: 0), // delivered
      message(2, 2, delivery: 64), // network accepted, delivery failed
      message(3, 5), // radio rejected send
      message(4, 4), // in outbox
      message(5, 6), // queued
      message(6, 3), // draft
    ], now);
    final month = result.periods[ReportPeriod.month]!;
    expect(month.sent, 2);
    expect(month.failed, 1);
    expect(month.awaiting, 3);
    expect(month.deliveryFailed, 1);
    expect(month.trendOut.fold<int>(0, (x, y) => x + y), 2);
  });
}
