import 'message_logic.dart';

/// Unicode-tolerant, entirely on-device SMS search. Never sends SMS to a server.
class MessageSearch {
  static final RegExp _marks = RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]');
  static const String _fa = '۰۱۲۳۴۵۶۷۸۹';
  static const String _ar = '٠١٢٣٤٥٦٧٨٩';

  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      var ch = String.fromCharCode(rune);
      if (_marks.hasMatch(ch)) continue;
      final fa = _fa.indexOf(ch);
      if (fa >= 0) { buffer.write(fa); continue; }
      final ar = _ar.indexOf(ch);
      if (ar >= 0) { buffer.write(ar); continue; }
      switch (ch) {
        case 'ي':
        case 'ى':
          ch = 'ی';
        case 'ك':
          ch = 'ک';
        case 'ة':
          ch = 'ه';
        case 'أ':
        case 'إ':
        case 'آ':
          ch = 'ا';
        case '\u200c':
        case '\u200d':
          ch = ' ';
      }
      buffer.write(ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Terms are normalized once per search, while inbox text is indexed only
  /// when the underlying message revision changes. The index stays on-device.
  static List<String> terms(String query) {
    final needle = normalize(query);
    return needle.isEmpty ? const <String>[] : needle.split(' ');
  }

  static bool containsTerms(String normalizedSource, List<String> terms) =>
      terms.isNotEmpty && terms.every(normalizedSource.contains);

  /// Supports individual words and multiword searches regardless of word order.
  static bool matches(String source, String query) =>
      containsTerms(normalize(source), terms(query));

  static List<MessageRecord> withinConversation(
    List<MessageRecord> messages, String query,
  ) {
    if (normalize(query).isEmpty) return const [];
    return [for (final message in messages) if (matches(message.body, query)) message];
  }
}
