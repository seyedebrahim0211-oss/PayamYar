import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'conversation_logic.dart';

/// A local broadcast list, NOT a real shared MMS/RCS conversation.
class SmsGroup {
  final String id;
  final String name;
  final List<String> recipients;
  final DateTime createdAt;
  const SmsGroup(this.id, this.name, this.recipients, this.createdAt);
  factory SmsGroup.fromJson(Map<String, dynamic> data) => SmsGroup(
    data['id'] as String,
    data['name'] as String,
    (data['recipients'] as List).whereType<String>().toList(growable: false),
    DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'recipients': recipients,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}

class SmsGroupStore extends ChangeNotifier {
  static const storageKey = 'payamyar_sms_groups_v1';
  static const maxMembers = 500;
  final List<SmsGroup> _groups = [];
  List<SmsGroup> get groups => List.unmodifiable(_groups);
  static String normalize(String address) => ConversationLogic.normalize(address);
  static List<String> uniqueRecipients(Iterable<String> values) =>
      values.map(normalize).where((v) => RegExp(r'^0\d{10}$|^\+?\d{7,15}$').hasMatch(v)).toSet().toList();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _groups.clear();
    for (final row in p.getStringList(storageKey) ?? const <String>[]) {
      try {
        final parsed = SmsGroup.fromJson(jsonDecode(row) as Map<String, dynamic>);
        if (parsed.name.trim().isNotEmpty && parsed.recipients.isNotEmpty &&
            parsed.recipients.length <= maxMembers) {
          _groups.add(parsed);
        }
      } catch (_) { /* Skip malformed local groups without affecting SMS. */ }
    }
    notifyListeners();
  }

  Future<SmsGroup> save(String name, Iterable<String> numbers, {String? id}) async {
    final title = name.trim();
    final members = uniqueRecipients(numbers);
    if (title.isEmpty || title.length > 60) {
      throw ArgumentError('نام گروه باید بین ۱ تا ۶۰ حرف باشد.');
    }
    if (members.length < 2 || members.length > maxMembers) {
      throw ArgumentError('هر گروه باید بین ۲ تا ۵۰۰ شماره معتبر داشته باشد.');
    }
    final existing = id == null ? -1 : _groups.indexWhere((g) => g.id == id);
    final previous = existing >= 0 ? _groups[existing] : null;
    final item = SmsGroup(previous?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title, members, previous?.createdAt ?? DateTime.now());
    if (existing >= 0) {
      _groups[existing] = item;
    } else {
      _groups.insert(0, item);
    }
    await _persist();
    notifyListeners();
    return item;
  }

  Future<void> remove(String id) async {
    _groups.removeWhere((g) => g.id == id);
    await _persist();
    notifyListeners();
  }
  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(storageKey, _groups.map((g) => jsonEncode(g.toJson())).toList());
  }
}
