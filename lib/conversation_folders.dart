import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'conversation_logic.dart';

/// Local-only folders. Assigning a conversation never modifies, moves or
/// deletes the device's SMS content. User-customized categories are private
/// to this app install and are not synced to the support server.
class ConversationFolders extends ChangeNotifier {
  static const _titlesKey = 'payamyar_folders_v1';
  static const _membersKey = 'payamyar_folder_members_v1';
  final List<String> _titles = [];
  final Map<String, String> _members = {};

  List<String> get titles => List.unmodifiable(_titles);
  String? forAddress(String address) => _members[ConversationLogic.normalize(address)];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _titles
      ..clear()
      ..addAll((prefs.getStringList(_titlesKey) ?? const <String>[])
        .where((name) => name.trim().isNotEmpty).take(20));
    _members.clear();
    try {
      final raw = prefs.getString(_membersKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is String && entry.value is String && _titles.contains(entry.value)) {
              _members[entry.key as String] = entry.value as String;
            }
          }
        }
      }
    } catch (_) { /* Invalid local data must not block messages. */ }
    notifyListeners();
  }
  Future<bool> create(String value) async {
    final title = value.trim();
    if (title.isEmpty || title.length > 30 || _titles.length >= 20 || _titles.contains(title)) return false;
    _titles.add(title);
    await _persist();
    return true;
  }
  Future<void> assign(String address, String? title) async {
    if (title != null && !_titles.contains(title)) return;
    final key = ConversationLogic.normalize(address);
    if (title == null) {
      _members.remove(key);
    } else {
      _members[key] = title;
    }
    await _persist();
  }
  Future<void> remove(String title) async {
    _titles.remove(title);
    _members.removeWhere((_, value) => value == title);
    await _persist();
  }
  Future<void> _persist() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_titlesKey, _titles);
    await prefs.setString(_membersKey, jsonEncode(_members));
  }
}
