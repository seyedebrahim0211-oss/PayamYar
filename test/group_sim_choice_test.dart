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
}
