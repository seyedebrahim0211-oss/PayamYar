import 'message_logic.dart';

class Conversation {
  final String address;
  final List<MessageRecord> messages;
  const Conversation(this.address, this.messages);
  MessageRecord get latest => messages.first;
  int get count => messages.length;
}
class ConversationLogic {
  static String normalize(String address) {
    var value = address.trim().replaceAll(RegExp(r'[\s()-]'), '');
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    value = value.split('').map((c) {
      final p = persian.indexOf(c);
      if (p >= 0) return p.toString();
      final a = arabic.indexOf(c);
      return a >= 0 ? a.toString() : c;
    }).join();
    if (RegExp(r'^(\+98|0098)9\d{9}.hasMatch(value)) {
      return '0${value.substring(value.length - 10)}';
    }
    return value.toLowerCase();
  }
  static List<Conversation> group(Iterable<MessageRecord> records) {
    final groups = <String, List<MessageRecord>>{};
    final labels = <String, String>{};
    for (final message in records) {
      final key = normalize(message.sender);
      (groups[key] ??= []).add(message);
      labels.putIfAbsent(key, () => message.sender);
    }
    final result = <Conversation>[];
    for (final entry in groups.entries) {
      entry.value.sort((a, b) => b.date.compareTo(a.date));
      result.add(Conversation(labels[entry.key]!, entry.value));
    }
    result.sort((a, b) => b.latest.date.compareTo(a.latest.date));
    return result;
  }
}
).hasMatch(value)) {
      return '0${value.substring(value.length - 10)}';
    }
    return value.toLowerCase();
  }
  static List<Conversation> group(Iterable<MessageRecord> records) {
    final groups = <String, List<MessageRecord>>{};
    final labels = <String, String>{};
    for (final message in records) {
      final key = normalize(message.sender);
      (groups[key] ??= []).add(message);
      labels.putIfAbsent(key, () => message.sender);
    }
    final result = <Conversation>[];
    for (final entry in groups.entries) {
      entry.value.sort((a, b) => b.date.compareTo(a.date));
      result.add(Conversation(labels[entry.key]!, entry.value));
    }
    result.sort((a, b) => b.latest.date.compareTo(a.latest.date));
    return result;
  }
}
