import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/contacts/contacts_data.dart';
import 'package:payamyar/contacts/contact_store.dart';

void main() {
  test('Jalali 30 Esfand without a birth year is preserved exactly', () {
    final contact = const PhoneContact(id: 7, name: 'نمونه',
      birthday: '--03-20').withBirthdayOverride([0, 12, 30]);
    expect(contact.jalaliBirthday, [0, 12, 30]);
    expect(jalaliBirthdayText(contact.birthday), isNotEmpty);
  });

  test('contact group membership stores its stable lookup key', () {
    const original = PhoneContact(id: 7, lookup: 'android:lookup:7',
      name: 'نمونه', birthday: '--03-20');
    final changed = original.withBirthdayOverride([0, 12, 30]);
    expect(changed.key, original.key);
    expect(changed.jalaliBirthday, [0, 12, 30]);
  });
}
