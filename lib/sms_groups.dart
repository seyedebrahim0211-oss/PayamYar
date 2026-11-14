import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'conversation_logic.dart';
import 'security/vault.dart';

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

/// One locally logged SMS broadcast: no SMS text is stored in preferences.
/// The body is encrypted separately in Android Keystore-backed Vault.
class SmsGroupBatch {
  final String id;
  final String groupId;
  final Map<String, int> acceptedAt;
  final DateTime createdAt;
  const SmsGroupBatch(this.id, this.groupId, this.acceptedAt, this.createdAt);

  factory SmsGroupBatch.fromJson(Map<String, dynamic> json) => SmsGroupBatch(
    json['id'] as String,
    json['groupId'] as String,
    (json['acceptedAt'] as Map).map((k, v) =>
      MapEntry(k.toString(), (v as num).toInt())),
    DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt()),
  );

  Map<String, Object> toJson() => {
    'id': id,
    'groupId': groupId,
    'acceptedAt': acceptedAt,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  String get vaultKey => 'groupmsg_$id';
}

class SmsGroupStore extends ChangeNotifier {
  static const storageKey = 'payamyar_sms_groups_v1';
  static const batchKey = 'payamyar_group_batch_v1';
  static const maxMembers = 500;
  final List<SmsGroup> _groups = [];
  final List<SmsGroupBatch> _batches = [];
  List<SmsGroupBatch> batchesFor(String groupId) => List.unmodifiable(
    _batches.where((batch) => batch.groupId == groupId));
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
    _batches.clear();
    for (final encoded in p.getStringList(batchKey) ?? const <String>[]) {
      try {
        final batch = SmsGroupBatch.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
        if (batch.acceptedAt.isNotEmpty) _batches.add(batch);
      } catch (_) { /* Skip malformed metadata; original phone SMS is untouched. */ }
    }
    notifyListeners();
  }

  /// Record only numbers accepted into Android's queue, not all selected recipients.
  /// Message body is encrypted and never written to SharedPreferences or group JSON.
  Future<void> recordBatch(String groupId, String body, Map<String, DateTime> accepted) async {
    if (accepted.isEmpty || body.trim().isEmpty) return;
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final batch = SmsGroupBatch(id, groupId, {
      for (final entry in accepted.entries)
        normalize(entry.key): entry.value.millisecondsSinceEpoch,
    }, DateTime.now());
    await Vault.put(batch.vaultKey, body); // Throws if secure storage is unavailable.
    _batches.insert(0, batch);
    final old = _batches.length > 80 ? _batches.sublist(80) : <SmsGroupBatch>[];
    if (old.isNotEmpty) _batches.removeRange(80, _batches.length);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(batchKey, _batches.map((e) => jsonEncode(e.toJson())).toList());
    for (final expired in old) { await Vault.remove(expired.vaultKey); }
    notifyListeners();
  }

  Future<String?> batchBody(SmsGroupBatch batch) => Vault.get(batch.vaultKey);

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
    final deleted = _batches.where((batch) => batch.groupId == id).toList();
    _batches.removeWhere((batch) => batch.groupId == id);
    await _persist();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(batchKey, _batches.map((e) => jsonEncode(e.toJson())).toList());
    for (final batch in deleted) { await Vault.remove(batch.vaultKey); }
    notifyListeners();
  }
  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(storageKey, _groups.map((g) => jsonEncode(g.toJson())).toList());
  }
}
