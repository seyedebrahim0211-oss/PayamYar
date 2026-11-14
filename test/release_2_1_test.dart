import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/contacts/contact_store.dart';
import 'package:payamyar/contacts/contacts_data.dart';
import 'package:payamyar/report_logic.dart';

void main() {
  test('auto merge candidates require an identical phone or email, not just name', () {
    final store = ContactStore();
    store.contacts = const [
      PhoneContact(id: 1, lookup: 'one', name: 'علی', phones: [LabeledValue('09120000000')]),
      PhoneContact(id: 2, lookup: 'two', name: 'علی', phones: [LabeledValue('09350000000')]),
      PhoneContact(id: 3, lookup: 'three', name: 'رضا', phones: [LabeledValue('+98 912 000 0000')]),
    ];
    expect(store.duplicates, hasLength(1));
    expect(store.duplicates.single.map((c) => c.id).toSet(), {1, 3});
  });

  test('summary export contains aggregate data only', () {
    const p = PeriodInsight(received: 7, sent: 3, hours: [], weekdays: [], categories: {},
      trendLabels: ['شنبه', 'یکشنبه'], trendIn: [2, 5], trendOut: [1, 2],
      suspicious: 2, otp: 1, people: 4, days: 7);
    final rows = reportMetricsCsvRows(p, ReportPeriod.week);
    expect(rows.first, hasLength(4));
    expect(rows.map((r) => r.join('|')), contains('روند|شنبه|2|1'));
    expect(rows.map((r) => r.join('|')), contains('امنیت|مشکوک / کد تأیید|2|1'));
    expect(rows.every((r) => r.length == 4), isTrue);
  });
}
