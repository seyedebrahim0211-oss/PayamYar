import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/contacts/contacts_data.dart';

void main() {
  test('phone numbers are normalised for matching', () {
    expect(phoneKey('+98 912 123 4567'), '09121234567');
    expect(phoneKey('۰۹۱۲۱۲۳۴۵۶۷'), '09121234567');
    expect(phoneKey('00989121234567'), '09121234567');
    expect(isUntidy('+989121234567'), isTrue);
    expect(isUntidy('09121234567'), isFalse);
  });

  test('vCard with quoted-printable Persian name, several numbers and categories', () {
    const vcf = 'BEGIN:VCARD\r\nVERSION:2.1\r\n'
        'FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=D8=B9=D9=84=DB=8C\r\n'
        'TEL;CELL:09121234567\r\nTEL;WORK:02188776655\r\nEMAIL;WORK:a@b.ir\r\n'
        'BDAY:1990-05-12\r\nCATEGORIES:کار,دوستان\r\nEND:VCARD\r\n';
    final list = parseVcf(vcf);
    expect(list, hasLength(1));
    expect(list.single.name, 'علی');
    expect(list.single.phones.map((p) => p.type), [2, 3]);
    expect(list.single.emails.single.type, 2);
    expect(list.single.birthday, '1990-05-12');
    expect(list.single.groups, ['کار', 'دوستان']);
  });

  test('export to vCard and back keeps the fields', () {
    const c = PhoneContact(id: 1, lookup: 'k1', name: 'مریم; احمدی', phones: [LabeledValue('09350000000')],
        emails: [LabeledValue('m@x.ir', type: 1)], org: 'شرکت', note: 'خط اول\nخط دوم');
    final back = parseVcf(toVcf([c], groupsOf: {'k1': ['خانواده']})).single;
    expect(back.name, 'مریم; احمدی');
    expect(back.phones.single.value, '09350000000');
    expect(back.note, 'خط اول\nخط دوم');
    expect(back.groups, ['خانواده']);
  });

  test('Excel rows map by header titles and accept Jalali birthdays', () {
    final drafts = rowsToDrafts([
      ['گروه', 'نام', 'موبایل', 'تولد', 'ایمیل'],
      ['کار ، دوستان', 'رضا', '0912 111 2233 , 09350000000', '1369/02/22', 'r@x.ir'],
      ['', '', '', '', ''],
    ]);
    expect(drafts, hasLength(1));
    expect(drafts.single.name, 'رضا');
    expect(drafts.single.phones, hasLength(2));
    expect(drafts.single.groups, ['کار', 'دوستان']);
    expect(drafts.single.birthday, '1990-05-12');
  });

  test('CSV with quotes and Excel BOM', () {
    final rows = parseCsv('﻿نام,موبایل\r\n"کریمی, رضا",09120000000\r\n');
    expect(rows, [['نام', 'موبایل'], ['کریمی, رضا', '09120000000']]);
  });

  test('sample sheet round-trips through the importer', () {
    final drafts = rowsToDrafts([for (final r in sampleRows) List<String>.of(r)]);
    expect(drafts, hasLength(3));
    expect(drafts[1].groups, ['خانواده', 'دوستان']);
    expect(drafts[2].phones.map((p) => p.type), [2, 3]);
  });
}
