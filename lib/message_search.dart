import 'message_logic.dart';

/// Full-text SMS search on the device. Normalization handles Arabic/Persian
/// spelling, Unicode digits, diacritics, zero-width joins and punctuation.
/// Neither query nor message content is sent to a server.
class MessageSearch {
  static final RegExp _marks = RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]');
  static const String _fa = '۰۱۲۳۴۵۶۷۸۹';
  static const String _ar = '٠١٢٣٤٥٦٧٨٩';
  static const String _separators = r""".,،؛;:!?؟/\\|()[]{}<>"'`_+*=٪%#@&^~$-–—«»…""" ;

  /// Produces a comparable text corpus while retaining spaces between words.
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      var ch = String.fromCharCode(rune);
      if (ch == '\u200c' || ch == '\u200d' || ch == '\u200b' ||
          ch == '\u200e' || ch == '\u200f' || ch == '\ufeff' ||
          _separators.contains(ch) || ch.trim().isEmpty) {
        buffer.write(' ');
        continue;
      }
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
        case 'ۀ':
          ch = 'ه';
        case 'أ':
        case 'إ':
        case 'ٱ':
        case 'آ':
          ch = 'ا';
      }
      buffer.write(ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Every query word must occur; word order and punctuation are irrelevant.
  static List<String> terms(String query) {
    final needle = normalize(query);
    return needle.isEmpty ? const <String>[] : needle.split(' ');
  }

  static bool containsTerms(String normalizedSource, List<String> terms) =>
      terms.isNotEmpty && terms.every(normalizedSource.contains);

  static bool matches(String source, String query) =>
      containsTerms(normalize(source), terms(query));

  /// Restrict navigation to messages that actually contain every searched term.
  static List<MessageRecord> withinConversation(
    List<MessageRecord> messages, String query,
  ) {
    final tokens = terms(query);
    if (tokens.isEmpty) return const [];
    return [for (final message in messages)
      if (containsTerms(normalize(message.body), tokens)) message];
  }
}
