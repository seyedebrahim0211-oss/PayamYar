import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/group_sim_choice.dart';

void main() {
  const sims = <Map<dynamic, dynamic>>[
    {'id': -1, 'label': 'پیش‌فرض'},
    {'id': 11, 'label': 'سیم ۱'},
    {'id': 22, 'label': 'سیم ۲'},
  ];

  test('group SMS cannot pick a default SIM silently', () {
    expect(GroupSimChoice.active(null, sims), isNull);
    expect(GroupSimChoice.active(-1, sims), isNull);
    expect(GroupSimChoice.active(99, sims), isNull);
  });

  test('only an explicitly chosen active subscription is accepted', () {
    expect(GroupSimChoice.active(11, sims), 11);
    expect(GroupSimChoice.active(22, sims), 22);
    expect(GroupSimChoice.active(11, const []), isNull);
  });

  test('single SIM is resolved safely without Android default routing', () {
    const one = <Map<dynamic, dynamic>>[{'id': 11, 'label': 'سیم ۱'}];
    expect(GroupSimChoice.privateSend(-1, one), 11);
    expect(GroupSimChoice.privateSend(null, one), 11);
    expect(GroupSimChoice.privateSend(-1, const []), isNull);
  });

  test('dual SIM requires an active selection', () {
    expect(GroupSimChoice.privateSend(-1, sims), isNull);
    expect(GroupSimChoice.privateSend(null, sims), isNull);
    expect(GroupSimChoice.privateSend(99, sims), isNull);
    expect(GroupSimChoice.privateSend(22, sims), 22);
  });
}
