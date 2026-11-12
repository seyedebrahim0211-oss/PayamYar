import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../jalali.dart';

/// A phone number or e-mail address with its Android type (1 home, 2 mobile/work, 3 work…, 0 custom).
class LabeledValue {
  final String value;
  final int type;
  final String label;
  const LabeledValue(this.value, {this.type = 2, this.label = ''});

  Map<String, Object> toMap() => {'value': value, 'type': type, 'label': label};

  static LabeledValue fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    return LabeledValue(m['value']?.toString() ?? '',
        type: (m['type'] as num?)?.toInt() ?? 2, label: m['label']?.toString() ?? '');
  }
}

const phoneTypeNames = {2: 'موبایل', 1: 'منزل', 3: 'محل کار', 7: 'سایر', 0: 'دلخواه'};
const emailTypeNames = {1: 'شخصی', 2: 'کاری', 3: 'سایر'};

/// One person in the phone book.
class PhoneContact {
  final int id;
  final String lookup;
  final String name;
  final bool starred;
  final bool hasPhoto;
  final List<LabeledValue> phones;
  final List<LabeledValue> emails;
  final String org;
  final String title;
  final String note;
  /// Android form: "YYYY-MM-DD" or "--MM-DD" (Gregorian).
  final String birthday;
  final int updated;

  const PhoneContact({required this.id, this.lookup = '', required this.name, this.starred = false,
      this.hasPhoto = false, this.phones = const [], this.emails = const [], this.org = '', this.title = '',
      this.note = '', this.birthday = '', this.updated = 0});

  /// Stable key for app-side data (groups): lookup key when Android provides one.
  String get key => lookup.isNotEmpty ? lookup : 'id:$id';
  String get displayName => name.trim().isNotEmpty ? name.trim() : (phones.isNotEmpty ? phones.first.value : (emails.isNotEmpty ? emails.first.value : 'بی‌نام'));
  String get primaryPhone => phones.isEmpty ? '' : (phones.firstWhere((p) => p.type == 2, orElse: () => phones.first)).value;
  String get initial {
    final n = name.trim();
    return n.isEmpty ? '#' : String.fromCharCode(n.runes.first).toUpperCase();
  }

  static PhoneContact fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    List<LabeledValue> list(String k) => (m[k] is List ? m[k] as List : const []).map(LabeledValue.fromMap)
        .where((v) => v.value.isNotEmpty).toList();
    return PhoneContact(
      id: (m['id'] as num?)?.toInt() ?? 0,
      lookup: m['lookup']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      starred: m['starred'] == true,
      hasPhoto: m['hasPhoto'] == true,
      phones: list('phones'),
      emails: list('emails'),
      org: m['org']?.toString() ?? '',
      title: m['title']?.toString() ?? '',
      note: m['note']?.toString() ?? '',
      birthday: m['birthday']?.toString() ?? '',
      updated: (m['updated'] as num?)?.toInt() ?? 0,
    );
  }

  /// Jalali [year (0 if unknown), month, day] of the birthday, or null.
  List<int>? get jalaliBirthday {
    final m = RegExp(r'^(\d{4}|-)-?(\d{1,2})-(\d{1,2})').firstMatch(birthday.trim());
    if (m == null) return null;
    final known = m.group(1) != '-';
    final y = known ? int.parse(m.group(1)!) : 2000;
    final j = Jalali.fromGregorian(y, int.parse(m.group(2)!), int.parse(m.group(3)!));
    return [known ? j[0] : 0, j[1], j[2]];
  }
}

final _phoneChar = RegExp(r'[0-9+]');

/// Normalised form of a phone number for comparisons ("09121234567"; other numbers keep their digits).
String phoneKey(String raw) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in raw.split('')) {
    final p = fa.indexOf(ch), a = ar.indexOf(ch);
    if (p >= 0) {
      b.write(p);
    } else if (a >= 0) {
      b.write(a);
    } else if (_phoneChar.hasMatch(ch)) {
      b.write(ch);
    }
  }
  var s = b.toString();
  if (s.startsWith('+98')) s = '0${s.substring(3)}';
  if (s.startsWith('0098')) s = '0${s.substring(4)}';
  if (s.length == 10 && s.startsWith('9')) s = '0$s';
  return s;
}

/// True when a number is written in a non-standard way that [phoneKey] would tidy up.
bool isUntidy(String raw) {
  final k = phoneKey(raw);
  return k.isNotEmpty && k != raw.trim() && RegExp(r'^09\d{9}$').hasMatch(k);
}

bool isValidPhone(String raw) => phoneKey(raw).replaceAll('+', '').length >= 5;

/// Method channel for ContactsChannel.kt.
class ContactsBridge {
  static const _c = MethodChannel('ir.honarmardomi.payamyar/contacts');
  static bool get supported => Platform.isAndroid;

  static Future<Map<String, bool>> permissions() async {
    if (!supported) return {'read': false, 'write': false};
    return await _c.invokeMapMethod<String, bool>('permissions') ?? {'read': false, 'write': false};
  }

  static Future<bool> requestPermissions() async =>
      supported && (await _c.invokeMethod<bool>('requestPermissions') ?? false);

  static Future<List<PhoneContact>> list() async {
    if (!supported) return [];
    final raw = await _c.invokeListMethod<dynamic>('list') ?? [];
    return raw.map(PhoneContact.fromMap).toList();
  }

  static Future<Uint8List?> photo(int id) async {
    if (!supported) return null;
    try {
      return await _c.invokeMethod<Uint8List>('photo', {'id': id});
    } catch (_) {
      return null;
    }
  }

  /// Creates (id 0) or updates a contact; returns its contact id.
  static Future<int> save({int id = 0, required String name, List<LabeledValue> phones = const [],
      List<LabeledValue> emails = const [], String org = '', String title = '', String note = '', String birthday = '',
      bool clearBirthday = false, Uint8List? photo, bool removePhoto = false}) async {
    return await _c.invokeMethod<int>('save', {
      'id': id, 'name': name, 'phones': [for (final p in phones) p.toMap()], 'emails': [for (final e in emails) e.toMap()],
      'org': org, 'title': title, 'note': note, 'birthday': birthday, 'clearBirthday': clearBirthday,
      'photo': photo, 'removePhoto': removePhoto,
    }) ?? 0;
  }

  static Future<int> delete(List<int> ids) async => await _c.invokeMethod<int>('delete', {'ids': ids}) ?? 0;
  static Future<bool> star(int id, bool value) async => await _c.invokeMethod<bool>('star', {'id': id, 'value': value}) ?? false;
  static Future<bool> join(List<int> ids) async => await _c.invokeMethod<bool>('join', {'ids': ids}) ?? false;
  static Future<Uint8List?> pickPhoto() => _c.invokeMethod<Uint8List>('pickPhoto');

  static Future<bool> saveFile(String name, String mime, Uint8List bytes) async =>
      await _c.invokeMethod<bool>('saveFile', {'name': name, 'mime': mime, 'bytes': bytes}) ?? false;

  /// Lets the user choose a VCF, XLSX or CSV file; null when cancelled.
  static Future<({String name, Uint8List bytes})?> openFile() async {
    final r = await _c.invokeMapMethod<String, dynamic>('openFile', {
      'mimes': ['text/x-vcard', 'text/vcard', 'text/directory', 'text/csv', 'text/comma-separated-values',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-excel',
        'application/octet-stream', 'text/plain'],
    });
    if (r == null) return null;
    return (name: r['name']?.toString() ?? '', bytes: r['bytes'] as Uint8List);
  }

  static Future<Uint8List> xlsxWrite(List<List<String>> rows) async =>
      await _c.invokeMethod<Uint8List>('xlsxWrite', {'rows': rows}) ?? Uint8List(0);

  static Future<List<List<String>>> xlsxRead(Uint8List bytes) async {
    final raw = await _c.invokeListMethod<dynamic>('xlsxRead', {'bytes': bytes}) ?? [];
    return [for (final r in raw) [for (final c in r as List) c.toString()]];
  }

  static Future<void> importWithSystem(Uint8List vcf) => _c.invokeMethod<bool>('importWithSystem', {'bytes': vcf});
  static Future<void> openSystemEditor(int id) => _c.invokeMethod<bool>('openSystemEditor', {'id': id});
  static Future<void> dial(String number) => _c.invokeMethod<bool>('dial', {'number': number});
  static Future<void> email(String address) => _c.invokeMethod<bool>('email', {'address': address});
}

// ───────────── file formats ─────────────

/// A contact read from a file, before it is written to the phone.
class ContactDraft {
  String name;
  final List<LabeledValue> phones;
  final List<LabeledValue> emails;
  String org;
  String title;
  String note;
  String birthday; // Gregorian "YYYY-MM-DD" / "--MM-DD" or empty
  final List<String> groups;
  ContactDraft({this.name = '', List<LabeledValue>? phones, List<LabeledValue>? emails, this.org = '', this.title = '',
      this.note = '', this.birthday = '', List<String>? groups})
      : phones = phones ?? [],
        emails = emails ?? [],
        groups = groups ?? [];

  bool get isEmpty => name.trim().isEmpty && phones.isEmpty && emails.isEmpty;
}

/// vCard 2.1 / 3.0 / 4.0 reader (names, numbers, e-mails, organisation, note, birthday, categories).
List<ContactDraft> parseVcf(String text) {
  // Unfold continuation lines (RFC 6350) and quoted-printable soft breaks.
  final lines = <String>[];
  for (final raw in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += raw.substring(1);
    } else if (lines.isNotEmpty && lines.last.endsWith('=') && lines.last.toUpperCase().contains('QUOTED-PRINTABLE')) {
      lines[lines.length - 1] = lines.last.substring(0, lines.last.length - 1) + raw;
    } else {
      lines.add(raw);
    }
  }
  final out = <ContactDraft>[];
  ContactDraft? cur;
  for (final line in lines) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final head = line.substring(0, colon);
    var value = line.substring(colon + 1);
    final parts = head.split(';');
    final prop = parts.first.split('.').last.toUpperCase();
    final params = parts.skip(1).join(';').toUpperCase();
    if (prop == 'BEGIN' && value.toUpperCase().trim() == 'VCARD') {
      cur = ContactDraft();
      continue;
    }
    if (prop == 'END') {
      if (cur != null && !cur.isEmpty) out.add(cur);
      cur = null;
      continue;
    }
    if (cur == null) continue;
    if (params.contains('QUOTED-PRINTABLE')) value = _decodeQp(value);
    value = value.replaceAll(r'\n', '\n').replaceAll(r'\,', ',').replaceAll(r'\;', ';').trim();
    switch (prop) {
      case 'FN':
        cur.name = value;
      case 'N':
        if (cur.name.isEmpty) {
          final n = value.split(';');
          cur.name = [if (n.length > 3) n[3], if (n.length > 1) n[1], if (n.length > 2) n[2], n[0], if (n.length > 4) n[4]]
              .where((s) => s.trim().isNotEmpty).join(' ');
        }
      case 'TEL':
        final v = value.replaceFirst(RegExp('^tel:', caseSensitive: false), '');
        if (v.isNotEmpty) {
          final type = params.contains('HOME') ? 1 : params.contains('WORK') ? 3 : 2;
          cur.phones.add(LabeledValue(v, type: type));
        }
      case 'EMAIL':
        if (value.isNotEmpty) cur.emails.add(LabeledValue(value, type: params.contains('WORK') ? 2 : 1));
      case 'ORG':
        cur.org = value.split(';').first;
      case 'TITLE':
        cur.title = value;
      case 'NOTE':
        cur.note = value;
      case 'BDAY':
        cur.birthday = normalizeBirthday(value);
      case 'CATEGORIES':
        cur.groups.addAll(value.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty && g.toLowerCase() != 'mycontacts'));
    }
  }
  return out;
}

String _decodeQp(String s) {
  final bytes = <int>[];
  var i = 0;
  while (i < s.length) {
    if (s[i] == '=' && i + 2 < s.length) {
      final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
      if (v != null) {
        bytes.add(v);
        i += 3;
        continue;
      }
    }
    bytes.addAll(utf8.encode(s[i]));
    i++;
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _vEsc(String s) => s.replaceAll(r'\', r'\\').replaceAll('\n', r'\n').replaceAll(',', r'\,').replaceAll(';', r'\;');

/// vCard 3.0 for any phone or e-mail program. Group names go into CATEGORIES.
String toVcf(Iterable<PhoneContact> contacts, {Map<String, List<String>> groupsOf = const {}}) {
  final b = StringBuffer();
  for (final c in contacts) {
    b.write('BEGIN:VCARD\r\nVERSION:3.0\r\n');
    b.write('FN:${_vEsc(c.displayName)}\r\nN:;${_vEsc(c.displayName)};;;\r\n');
    for (final p in c.phones) {
      final t = p.type == 1 ? 'HOME' : p.type == 3 ? 'WORK' : 'CELL';
      b.write('TEL;TYPE=$t:${p.value}\r\n');
    }
    for (final e in c.emails) {
      b.write('EMAIL;TYPE=${e.type == 2 ? 'WORK' : 'HOME'}:${e.value}\r\n');
    }
    if (c.org.isNotEmpty) b.write('ORG:${_vEsc(c.org)}\r\n');
    if (c.title.isNotEmpty) b.write('TITLE:${_vEsc(c.title)}\r\n');
    if (c.note.isNotEmpty) b.write('NOTE:${_vEsc(c.note)}\r\n');
    if (c.birthday.isNotEmpty) b.write('BDAY:${c.birthday}\r\n');
    final groups = groupsOf[c.key] ?? const [];
    if (groups.isNotEmpty) b.write('CATEGORIES:${groups.map(_vEsc).join(',')}\r\n');
    b.write('END:VCARD\r\n');
  }
  return b.toString();
}

/// Accepts Gregorian (1990-05-12, 19900512, --05-12) or Jalali (1369/02/22, ۱۳۶۹-۰۲-۲۲) dates.
String normalizeBirthday(String raw) {
  final s = raw.trim().replaceAllMapped(RegExp('[۰-۹]'), (m) => (m.group(0)!.codeUnitAt(0) - 0x06F0).toString());
  if (s.isEmpty) return '';
  final noYear = RegExp(r'^--(\d{1,2})-?(\d{1,2})$').firstMatch(s);
  if (noYear != null) return '--${noYear.group(1)!.padLeft(2, '0')}-${noYear.group(2)!.padLeft(2, '0')}';
  final m = RegExp(r'^(\d{4})[-/.]?(\d{1,2})[-/.]?(\d{1,2})').firstMatch(s);
  if (m == null) return '';
  var y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return '';
  if (y < 1700) {
    final g = Jalali.toGregorian(y, mo, d);
    y = g[0];
    mo = g[1];
    d = g[2];
  }
  return '${y.toString().padLeft(4, '0')}-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// Shown as Jalali "1369/02/22" (or "02/22" without year) for tables and the editor.
String jalaliBirthdayText(String birthday) {
  final c = PhoneContact(id: 0, name: '', birthday: birthday).jalaliBirthday;
  if (c == null) return '';
  final md = '${c[1].toString().padLeft(2, '0')}/${c[2].toString().padLeft(2, '0')}';
  return c[0] == 0 ? md : '${c[0]}/$md';
}

/// Excel / CSV columns. The first row of the sample file uses these titles.
const sheetColumns = ['نام', 'موبایل', 'تلفن منزل', 'تلفن کار', 'ایمیل', 'ایمیل کاری', 'شرکت', 'سمت', 'گروه', 'تولد', 'یادداشت'];

List<List<String>> contactsToRows(Iterable<PhoneContact> contacts, Map<String, List<String>> groupsOf) {
  String phoneOf(PhoneContact c, int type, {bool fallback = false}) {
    final list = c.phones.where((p) => p.type == type).map((p) => p.value).toList();
    if (list.isEmpty && fallback) {
      list.addAll(c.phones.where((p) => p.type != 1 && p.type != 3).map((p) => p.value));
    }
    return list.join(' ، ');
  }

  return [
    sheetColumns,
    for (final c in contacts)
      [
        c.displayName,
        phoneOf(c, 2, fallback: true),
        phoneOf(c, 1),
        phoneOf(c, 3),
        c.emails.where((e) => e.type != 2).map((e) => e.value).join(' ، '),
        c.emails.where((e) => e.type == 2).map((e) => e.value).join(' ، '),
        c.org,
        c.title,
        (groupsOf[c.key] ?? const []).join(' ، '),
        jalaliBirthdayText(c.birthday),
        c.note,
      ],
  ];
}

const sampleRows = [
  sheetColumns,
  ['علی رضایی', '09121234567', '02188776655', '', 'ali@example.com', '', 'هنر مردمی', 'مدیر', 'کار', '1369/02/22', 'همکار پروژه'],
  ['مریم احمدی', '09359876543', '', '', '', 'maryam@company.ir', '', '', 'خانواده ، دوستان', '1372/11/05', ''],
  ['رضا کریمی', '+989101112233', '', '05632221100', '', '', 'بشرویه', '', 'دوستان', '', 'شماره‌ها را می‌توانید با «،» جدا کنید'],
];

/// Reads rows from Excel/CSV. Header titles are matched in Persian or English, in any order.
List<ContactDraft> rowsToDrafts(List<List<String>> rows) {
  if (rows.isEmpty) return [];
  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int find(List<String> names) => header.indexWhere((h) => names.any((n) => h == n || h.contains(n)));
  final iName = find(['نام', 'name', 'full name']);
  final iMobile = find(['موبایل', 'همراه', 'mobile', 'cell', 'phone']);
  final iHome = find(['منزل', 'home']);
  final iWork = find(['تلفن کار', 'work phone', 'office']);
  final iEmail = find(['ایمیل', 'email', 'e-mail']);
  final iEmailWork = find(['ایمیل کاری', 'work email']);
  final iOrg = find(['شرکت', 'سازمان', 'company', 'organization']);
  final iTitle = find(['سمت', 'title', 'job']);
  final iGroup = find(['گروه', 'group', 'category']);
  final iBirthday = find(['تولد', 'birthday', 'birth']);
  final iNote = find(['یادداشت', 'توضیح', 'note']);
  final hasHeader = iName >= 0 || iMobile >= 0;
  final body = hasHeader ? rows.skip(1) : rows;
  String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';
  List<String> split(String s) => s.split(RegExp(r'\s*[،,;|]\s*')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  final out = <ContactDraft>[];
  for (final r in body) {
    final d = ContactDraft(
      name: at(r, hasHeader ? iName : 0),
      org: at(r, iOrg),
      title: at(r, iTitle),
      note: at(r, iNote),
      birthday: normalizeBirthday(at(r, iBirthday)),
      groups: split(at(r, iGroup)),
    );
    for (final v in split(at(r, hasHeader ? iMobile : 1))) {
      d.phones.add(LabeledValue(v, type: 2));
    }
    for (final v in split(at(r, iHome))) {
      d.phones.add(LabeledValue(v, type: 1));
    }
    if (iWork != iMobile) {
      for (final v in split(at(r, iWork))) {
        d.phones.add(LabeledValue(v, type: 3));
      }
    }
    for (final v in split(at(r, iEmail))) {
      d.emails.add(LabeledValue(v, type: 1));
    }
    if (iEmailWork != iEmail) {
      for (final v in split(at(r, iEmailWork))) {
        d.emails.add(LabeledValue(v, type: 2));
      }
    }
    if (!d.isEmpty) out.add(d);
  }
  return out;
}

/// Minimal CSV reader (quotes, commas, semicolons or tabs as separator).
List<List<String>> parseCsv(String text) {
  final src = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final firstLine = src.split('\n').first;
  final sep = firstLine.contains('\t') ? '\t' : (firstLine.split(';').length > firstLine.split(',').length ? ';' : ',');
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < src.length; i++) {
    final ch = src[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < src.length && src[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < src.length && src[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString());
  if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
  return rows;
}
