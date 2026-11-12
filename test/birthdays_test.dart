import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/birthdays.dart';
import 'package:payamyar/jalali.dart';

void main() {
  test('greeting fills name, full name and age', () {
    const b = Birthday(id: '1', name: 'علی رضایی', number: '09120000000', month: 8, day: 21, year: 1370,
        message: '{نام} جان تولد {سن} سالگی مبارک — {نام کامل}');
    expect(b.render(1405), 'علی جان تولد ${Jalali.digits(35)} سالگی مبارک — علی رضایی');
  });

  test('unknown birth year leaves age empty', () {
    const b = Birthday(id: '1', name: 'سارا', number: '09120000000', month: 1, day: 1, message: 'تولد {سن} مبارک {نام}');
    expect(b.render(1405), 'تولد مبارک سارا');
  });

  test('days until today is zero and JSON round-trips', () {
    final now = DateTime.now();
    final j = Jalali.fromGregorian(now.year, now.month, now.day);
    expect(daysUntil(j[1], j[2]), 0);
    final b = Birthday(id: 'x', name: 'n', number: '09120000000', month: j[1], day: j[2], hour: 8, minute: 30);
    final back = Birthday.fromJson(b.toJson())!;
    expect(back.hour, 8);
    expect(back.minute, 30);
    expect(back.month, j[1]);
  });
}
