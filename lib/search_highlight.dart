import 'package:flutter/material.dart';
import 'message_search.dart';

/// Maps normalized matches back to the original UTF-16 offsets for display.
TextSpan searchHighlight(String source, String query) {
  final terms = MessageSearch.terms(query);
  if (terms.isEmpty || source.isEmpty) return TextSpan(text: source);
  final compact = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var offset = 0;
  for (final rune in source.runes) {
    final original = String.fromCharCode(rune);
    final folded = MessageSearch.normalize(original);
    compact.write(folded);
    starts.addAll(List.filled(folded.length, offset));
    offset += original.length;
    ends.addAll(List.filled(folded.length, offset));
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
