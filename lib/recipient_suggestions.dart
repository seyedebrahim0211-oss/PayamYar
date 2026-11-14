import 'message_logic.dart';
import 'sms_bridge.dart';

/// Local contact ranking. No message body is inspected or uploaded.
class RecipientSuggestions {
  static String key(String value) {
    final raw = SmsBridge.normalizeNumber(value).replaceAll(RegExp(r'[^0-9+]'), '');
    if (raw.startsWith('+98') && raw.length == 13) return '0${raw.substring(3)}';
    if (raw.startsWith('0098') && raw.length == 14) return '0${raw.substring(4)}';
    if (raw.startsWith('98') && raw.length == 12) return '0${raw.substring(2)}';
    return raw;
  }

  static Map<String, int> frequency(List<MessageRecord> messages) {
    final scores = <String, int>{};
    for (final message in messages) {
      if (!message.outgoing) continue;
      final phone = key(message.sender);
      if (phone.isEmpty || !RegExp(r'^0[0-9]{10}$').hasMatch(phone)) continue;
      scores[phone] = (scores[phone] ?? 0) + 1;
    }
    return scores;
  }

  static List<Map<String, String>> rank(
    List<Map<String, String>> contacts, Map<String, int> frequency, String query, {
      Set<String> excluded = const {},
      int limit = 8,
    }) {
    final term = SmsBridge.normalizeNumber(query).toLowerCase().trim();
    final normalizedTerm = key(term);
    final matched = contacts.where((contact) {
      final number = key(contact['number'] ?? '');
      if (excluded.contains(number)) return false;
      if (term.isEmpty) return true;
      return (contact['name'] ?? '').toLowerCase().contains(term) ||
        number.contains(normalizedTerm);
    }).toList();
    matched.sort((a, b) {
      final an = key(a['number'] ?? '');
      final bn = key(b['number'] ?? '');
      final aExact = term.isNotEmpty && (an == normalizedTerm ||
        (a['name'] ?? '').toLowerCase().startsWith(term)) ? 1 : 0;
      final bExact = term.isNotEmpty && (bn == normalizedTerm ||
        (b['name'] ?? '').toLowerCase().startsWith(term)) ? 1 : 0;
      if (aExact != bExact) return bExact.compareTo(aExact);
      final popularity = (frequency[bn] ?? 0).compareTo(frequency[an] ?? 0);
      return popularity != 0 ? popularity : (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    return matched.take(limit).toList(growable: false);
  }
}
