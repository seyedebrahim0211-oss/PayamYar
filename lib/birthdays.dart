import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'jalali.dart';
import 'sms_bridge.dart';

/// One contact's birthday and how PayamYar greets them.
/// Stored as JSON under "birthdays_v1"; Birthdays.kt reads the same keys natively.
class Birthday {
  final String id;
  final String name;
  final String number;
  final int month; // Jalali 1..12
  final int day; // 1..31
  final int year; // Jalali birth year, 0 = unknown
  final int hour;
  final int minute;
  final String message;
  final bool enabled;
  final bool autoSend;
  final bool remind;

  const Birthday({required this.id, required this.name, required this.number, required this.month,
      required this.day, this.year = 0, this.hour = 9, this.minute = 0, this.message = defaultBirthdayMessage,
      this.enabled = true, this.autoSend = true, this.remind = true});

  Birthday copyWith({String? name, String? number, int? month, int? day, int? year, int? hour, int? minute,
          String? message, bool? enabled, bool? autoSend, bool? remind}) =>
      Birthday(id: id, name: name ?? this.name, number: number ?? this.number, month: month ?? this.month,
          day: day ?? this.day, year: year ?? this.year, hour: hour ?? this.hour, minute: minute ?? this.minute,
          message: message ?? this.message, enabled: enabled ?? this.enabled, autoSend: autoSend ?? this.autoSend,
          remind: remind ?? this.remind);

  Map<String, Object> toJson() => {
        'id': id, 'name': name, 'number': number, 'month': month, 'day': day, 'year': year,
        'hour': hour, 'minute': minute, 'message': message, 'enabled': enabled,
        'autoSend': autoSend, 'remind': remind,
      };

  static Birthday? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int i(String k, int d) => raw[k] is num ? (raw[k] as num).toInt() : d;
    bool b(String k) => raw[k] is bool ? raw[k] as bool : true;
    final id = raw['id']?.toString() ?? '';
    final number = raw['number']?.toString() ?? '';
    final month = i('month', 0), day = i('day', 0);
    if (id.isEmpty || number.isEmpty || month < 1 || month > 12 || day < 1 || day > 31) return null;
    return Birthday(id: id, name: raw['name']?.toString() ?? number, number: number, month: month, day: day,
        year: i('year', 0), hour: i('hour', 9).clamp(0, 23).toInt(), minute: i('minute', 0).clamp(0, 59).toInt(),
        message: raw['message']?.toString() ?? defaultBirthdayMessage,
        enabled: b('enabled'), autoSend: b('autoSend'), remind: b('remind'));
  }

  String get dateLabel => '${Jalali.digits(day)} ${Jalali.months[month - 1]}';
  String get timeLabel => Jalali.digits('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');

  /// Age they turn on their next birthday, or null when the birth year is unknown.
  int? ageOn(int jalaliYear) => year >= 1200 && year <= jalaliYear ? jalaliYear - year : null;

  /// The text that will be sent, with {نام}, {نام کامل} and {سن} filled in.
  String render(int jalaliYear) {
    final full = name.trim();
    final parts = full.split(' ').where((p) => p.isNotEmpty);
    final first = parts.isEmpty ? full : parts.first;
    final age = ageOn(jalaliYear);
    return message.replaceAll('{نام کامل}', full).replaceAll('{نام}', first)
        .replaceAll('{سن}', age == null ? '' : Jalali.digits(age)).replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }
}

const defaultBirthdayMessage = '{نام} عزیز، تولدت مبارک! 🎂\nآرزوی سالی پر از شادی و سلامتی برایت دارم.';

const birthdayTemplates = [
  defaultBirthdayMessage,
  'سلام {نام} جان 🌸 تولد {سن} سالگی‌ات مبارک! همیشه خندان باشی.',
  '{نام کامل} گرامی، زادروزتان خجسته باد. 💐',
  'تولدت مبارک رفیق! 🎉 امیدوارم امسال بهترین سال زندگیت باشه.',
];

/// Days until the next occurrence of a Jalali month/day, 0 = today.
int daysUntil(int month, int day, {DateTime? now}) {
  final start = now ?? DateTime.now();
  final today = DateTime(start.year, start.month, start.day);
  for (var i = 0; i < 400; i++) {
    final d = today.add(Duration(days: i));
    final j = Jalali.fromGregorian(d.year, d.month, d.day);
    if (j[1] == month && j[2] == day) return i;
    // 30 Esfand in a common year is celebrated on 29 Esfand.
    if (month == 12 && day == 30 && j[1] == 12 && j[2] == 29) {
      final n = d.add(const Duration(days: 1));
      if (Jalali.fromGregorian(n.year, n.month, n.day)[1] == 1) return i;
    }
  }
  return 400;
}

class BirthdayStore extends ChangeNotifier {
  static const key = 'birthdays_v1';
  List<Birthday> items = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(p.getString(key) ?? '[]');
      items = raw is List ? raw.map(Birthday.fromJson).whereType<Birthday>().toList() : [];
    } catch (_) {
      items = [];
    }
    notifyListeners();
  }

  /// Sorted by the next birthday first.
  List<Birthday> get upcoming =>
      [...items]..sort((a, b) => daysUntil(a.month, a.day).compareTo(daysUntil(b.month, b.day)));

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode([for (final b in items) b.toJson()]));
    notifyListeners();
    await SmsBridge.birthdaysChanged();
  }

  Future<void> upsert(Birthday b) async {
    final i = items.indexWhere((x) => x.id == b.id);
    if (i < 0) {
      items = [...items, b];
    } else {
      items = [...items]..[i] = b;
    }
    await _save();
  }

  Future<void> remove(String id) async {
    items = items.where((b) => b.id != id).toList();
    await _save();
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
