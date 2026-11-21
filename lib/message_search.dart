import 'message_logic.dart';

/// Full-text SMS search on the device. Normalization handles Arabic/Persian
/// spelling, Unicode digits, diacritics, zero-width joins and punctuation.
/// Neither query nor message content is sent to a server.
class MessageSearch {
  static final RegExp _marks = RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]');
  static const String _fa = '۰۱۲۳۴۵۶۷۸۹';
  static const String _ar = '٠١٢٣٤٥٦٧٨٩';
  static const String _separators = r""".,،؛;:!?؟/\\|()[]{}<>"'`_+*=٪%#@&^~$-–—«»…٬٫""" ;

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

  // MessageRecord.body is immutable; weak keys release this cache when SMS
  // history is refreshed. Inbox tiles and per-chat search share one index.
  static final Expando<String> _indexedBodies = Expando<String>('sms-search');
  static String indexedBody(MessageRecord message) =>
      _indexedBodies[message] ??= normalize(message.body);

  /// Iranian mobile numbers match across 09, +98 and 0098 spellings.
  /// Index only in memory; never upload phone numbers for search.
  static String phoneAliases(String raw) {
    final digits = normalize(raw).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('09')) {
      final international = '98${digits.substring(1)}';
      return '$international 00$international';
    }
    if (digits.length == 12 && digits.startsWith('989')) {
      return '0${digits.substring(2)} 00$digits';
    }
    if (digits.length == 14 && digits.startsWith('00989')) {
      return '0${digits.substring(4)} ${digits.substring(2)}';
    }
    return '';
  }
  /// Every query word must occur; word order and punctuation are irrelevant.
  static List<String> terms(String query) {
    final needle = normalize(query);
    return needle.isEmpty ? const <String>[] : needle.split(' ');
  }

  static bool containsTerms(String normalizedSource, List<String> terms) {
    if (terms.isEmpty) return false;
    // Avoid allocating a missing-token list and compacting every message.
    String? compact;
    for (final term in terms) {
      if (normalizedSource.contains(term)) continue;
      compact ??= normalizedSource.replaceAll(' ', '');
      if (!compact.contains(term)) return false;
    }
    return true;
  }

  static bool matches(String source, String query) =>
      containsTerms(normalize(source), terms(query));

  /// Give input, scrolling and cancellation a turn during a large local scan.
  static Future<List<MessageRecord>> scan(List<MessageRecord> rows, List<String> tokens,
      Stopwatch budget, bool Function() cancelled) async {
    final hits = <MessageRecord>[];
    for (var i = 0; i < rows.length; i++) {
      if (budget.elapsedMicroseconds >= 3500) {
        await Future<void>.delayed(Duration.zero);
        if (cancelled()) return const [];
        budget.reset();
      }
      final message = rows[i];
      if (containsTerms(indexedBody(message), tokens)) hits.add(message);
    }
    return hits;
  }

  /// Restrict navigation to messages that actually contain every searched term.
  static List<MessageRecord> withinConversation(
    List<MessageRecord> messages, String query,
  ) {
    final tokens = terms(query);
    if (tokens.isEmpty) return const [];
    return [for (final message in messages)
      if (containsTerms(indexedBody(message), tokens)) message];
  }
}
