import 'message_logic.dart';
import 'sms_bridge.dart';
import 'message_search.dart';

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
    final tokens = MessageSearch.terms(query);
    final prefix = tokens.join(' ');
    final numericQuery = RegExp(r'^[+0-9۰-۹٠-٩ ()-]+$').hasMatch(query) ? key(query) : '';
    final ranked = <({Map<String, String> contact, String name, int hits, int score})>[];
    for (final contact in contacts) {
      final number = key(contact['number'] ?? '');
      if (excluded.contains(number)) continue;
      final name = contact['name'] ?? '';
      final folded = MessageSearch.normalize(name);
      if (tokens.isNotEmpty && !(numericQuery.isNotEmpty && number.contains(numericQuery)) && !MessageSearch.containsTerms('$folded $number', tokens) &&
          !MessageSearch.containsTerms('$folded ${MessageSearch.normalize(contact['number'] ?? '')}', tokens)) {
        continue;
      }
      final exact = prefix.isNotEmpty && (folded.startsWith(prefix) || number == numericQuery);
      ranked.add((contact: contact, name: name, hits: exact ? 1 : 0, score: frequency[number] ?? 0));
    }
    ranked.sort((a, b) {
      final relevance = b.hits.compareTo(a.hits);
      if (relevance != 0) return relevance;
      final popularity = b.score.compareTo(a.score);
      return popularity == 0 ? a.name.compareTo(b.name) : popularity;
    });
    return ranked.take(limit).map((entry) => entry.contact).toList(growable: false);
  }
}
