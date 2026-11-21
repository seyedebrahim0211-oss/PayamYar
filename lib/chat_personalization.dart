import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// Local-only visual preferences. SMS content, photos and wallpaper are never
/// transferred to the website. Pictures are copied out of the picker cache into
/// app-private storage; deleting the application removes them.
class ChatRoomStyle {
  final ChatStyle? theme;
  final String? avatarPath;
  final String? wallpaperPath;

  const ChatRoomStyle({this.theme, this.avatarPath, this.wallpaperPath});

  ChatRoomStyle withTheme(ChatStyle? next) => ChatRoomStyle(
    theme: next, avatarPath: avatarPath, wallpaperPath: wallpaperPath);

  ChatRoomStyle withImage({required bool wallpaper, String? path}) => ChatRoomStyle(
    theme: theme,
    avatarPath: wallpaper ? avatarPath : path,
    wallpaperPath: wallpaper ? path : wallpaperPath);

  Map<String, Object?> toJson() => {
    'theme': theme?.index,
    'avatar': avatarPath,
    'wallpaper': wallpaperPath,
  };

  static ChatRoomStyle fromJson(Object? value) {
    if (value is! Map) return const ChatRoomStyle();
    final rawTheme = value['theme'];
    final index = rawTheme is int ? rawTheme : -1;
    return ChatRoomStyle(
      theme: index >= 0 && index < ChatStyle.values.length ? ChatStyle.values[index] : null,
      avatarPath: value['avatar'] is String ? value['avatar'] as String : null,
      wallpaperPath: value['wallpaper'] is String ? value['wallpaper'] as String : null,
    );
  }
}

/// Small global notifier: visible inbox avatars react immediately to changes
/// made in a conversation. Keyed by the canonical number, not contact display name.
class ChatPersonalizations extends ChangeNotifier {
  ChatPersonalizations._();
  static final instance = ChatPersonalizations._();
  static const _key = 'payamyar.chat.visual.v1';
  static const maxImageBytes = 4 * 1024 * 1024;
  final Map<String, ChatRoomStyle> _rooms = {};
  Future<void>? _loading;
  SharedPreferences? _prefs;

  static String canonical(String address) {
    final text = address.trim();
    final number = text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.startsWith('+98') && number.length == 13) return '0${number.substring(3)}';
    if (number.startsWith('0098') && number.length == 14) return '0${number.substring(4)}';
    if (number.startsWith('98') && number.length == 12) return '0${number.substring(2)}';
    return number.isNotEmpty && !RegExp(r'[a-zA-Zآ-ی]').hasMatch(text)
        ? number : text.toLowerCase();
  }

  ChatRoomStyle forAddress(String address) => _rooms[canonical(address)] ?? const ChatRoomStyle();

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        for (final entry in parsed.entries) {
          if (entry.key.length <= 120) _rooms[entry.key] = ChatRoomStyle.fromJson(entry.value);
        }
      }
      notifyListeners();
    } catch (_) {
      // Corrupt local visual preferences must never block SMS startup.
    }
  }

  Future<void> _persist() async {
    await load();
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      for (final entry in _rooms.entries) entry.key: entry.value.toJson(),
    }));
    notifyListeners();
  }

  Future<void> setTheme(String address, ChatStyle? theme) async {
    await load();
    final key = canonical(address);
    _rooms[key] = forAddress(key).withTheme(theme);
    await _persist();
  }

  /// Only JPEG, PNG and WEBP are accepted, with a strict size limit. No
  /// photo/media library permission, remote URL or third-party upload is used.
  static String? imageExtension(List<int> h) {
    if (h.length < 12) return null;
    if (h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF) { return 'jpg'; }
    if (h[0] == 0x89 && h[1] == 0x50 && h[2] == 0x4E && h[3] == 0x47 &&
        h[4] == 0x0D && h[5] == 0x0A && h[6] == 0x1A && h[7] == 0x0A) { return 'png'; }
    if (String.fromCharCodes(h.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(h.sublist(8, 12)) == 'WEBP') { return 'webp'; }
    return null;
  }

  /// Returns false when the Android picker is cancelled.
  Future<bool> chooseImage(String address, {required bool wallpaper}) async {
    final selected = await FilePicker.pickFile(type: FileType.image);
    if (selected == null) return false;
    if (selected.size < 12 || selected.size > maxImageBytes) {
      throw const FormatException('عکس باید کمتر از ۴ مگابایت باشد.');
    }
    // Some providers return a cached file path; Google Photos/cloud providers
    // may only expose a stream. Handle either without loading huge pictures.
    final path = selected.path;
    final source = path == null || path.startsWith('content:') ? null : File(path);
    final bytes = source == null ? await selected.readAsBytes() : null;
    final length = source == null ? bytes!.length : await source.length();
    if (length < 12 || length > maxImageBytes) {
      throw const FormatException('عکس باید کمتر از ۴ مگابایت باشد.');
    }
    final header = source == null ? bytes!.sublist(0, 12) : await source.openRead(0, 12).first;
    final ext = imageExtension(header);
    if (ext == null) {
      throw const FormatException('فقط عکس‌های JPG، PNG و WebP پشتیبانی می‌شوند.');
    }
    await load();
    final directory = Directory('${(await getApplicationSupportDirectory()).path}/payamyar_chats');
    await directory.create(recursive: true);
    final id = sha256.convert(utf8.encode(canonical(address))).toString();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final filename = '${id}_${wallpaper ? 'wall' : 'avatar'}_$stamp.$ext';
    final target = File('${directory.path}/$filename');
    if (source == null) {
      await target.writeAsBytes(bytes!, flush: true);
    } else {
      await source.copy(target.path);
    }

    final key = canonical(address);
    final previous = forAddress(key);
    final obsolete = wallpaper ? previous.wallpaperPath : previous.avatarPath;
    _rooms[key] = previous.withImage(wallpaper: wallpaper, path: target.path);
    await _persist();
    await _deleteOldImage(obsolete);
    return true;
  }

  Future<void> clearImage(String address, {required bool wallpaper}) async {
    await load();
    final key = canonical(address);
    final previous = forAddress(key);
    final old = wallpaper ? previous.wallpaperPath : previous.avatarPath;
    _rooms[key] = previous.withImage(wallpaper: wallpaper);
    await _persist();
    await _deleteOldImage(old);
  }

  Future<void> _deleteOldImage(String? path) async {
    if (path == null) return;
    try {
      final directory = Directory('${(await getApplicationSupportDirectory()).path}/payamyar_chats');
      if (!path.startsWith('${directory.path}/')) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) { /* A stale old image is harmless in private app storage. */ }
  }
}
