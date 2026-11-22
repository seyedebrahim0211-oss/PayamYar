import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../conversation_logic.dart';
import 'vault.dart';

class ChatDrafts {
  // Serializing reads and writes also covers leaving and immediately reopening a chat.
  static Future<void> _pending = Future.value();
  static String _key(String address) =>
      'chat_${sha256.convert(utf8.encode(ConversationLogic.normalize(address))).toString().substring(0, 32)}';
  static Future<String?> read(String address) async {
    await _pending;
    return Vault.get(_key(address));
  }
  static Future<void> save(String address, String text) {
    final key = _key(address);
    final write = _pending.then((_) => text.isEmpty ? Vault.remove(key) : Vault.put(key, text));
    _pending = write.catchError((Object _) {});
    return write;
  }
}
