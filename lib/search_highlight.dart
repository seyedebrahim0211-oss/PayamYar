import 'package:flutter/material.dart';
import 'message_search.dart';

/// Maps normalized matches back to the original UTF-16 offsets for display.
TextSpan searchHighlight(String source, String query) {
  final terms = MessageSearch.terms(query);
  if (terms.isEmpty || source.isEmpty) return TextSpan(text: source);
  final alphabet = <int, String>{};
  final compact = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var offset = 0;
  for (final rune in source.runes) {
    final original = String.fromCharCode(rune);
    final folded = alphabet[rune] ??= MessageSearch.normalize(original);
    compact.write(folded);
    for (var i = 0; i < folded.length; i++) {
      starts.add(offset);
      ends.add(offset + original.length);
    }
    offset += original.length;
  }
  final body = compact.toString();
  final ranges = <(int, int)>[];
  for (final term in terms.toSet()) {
    var pos = body.indexOf(term);
    while (pos >= 0) {
      ranges.add((starts[pos], ends[pos + term.length - 1]));
      pos = body.indexOf(term, pos + term.length);
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final spans = <TextSpan>[];
  var end = 0;
  for (final range in ranges) {
    if (range.$2 <= end) continue;
    if (range.$1 > end) spans.add(TextSpan(text: source.substring(end, range.$1)));
    final start = range.$1 < end ? end : range.$1;
    spans.add(TextSpan(text: source.substring(start, range.$2),
      style: const TextStyle(fontWeight: FontWeight.w900, backgroundColor: Color(0x5522BDB2))));
    end = range.$2;
  }
  spans.add(TextSpan(text: source.substring(end)));
  return TextSpan(children: spans);
}
