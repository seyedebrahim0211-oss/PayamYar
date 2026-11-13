import 'dart:convert';
import 'dart:typed_data';

/// CSV for Excel with a UTF-8 BOM (Persian text opens correctly).
///
/// Security: a cell that starts with = + - @ (or tab/CR) is executed as a formula by
/// Excel/Sheets ("CSV injection"). A contact name like `=HYPERLINK("http://evil",..)` received
/// from someone else could then run when the exported file is opened. Such cells are
/// prefixed with an apostrophe. Plain phone numbers like +989121234567 stay as they are.
String csvCell(String value) {
  var v = value;
  final phone = RegExp(r'^\+?[\d\s()-]{3,20}$').hasMatch(v);
  if (!phone && v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
  return '"${v.replaceAll('"', '""')}"';
}

String toCsv(List<List<String>> rows) => '﻿${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}';

Uint8List csvBytes(List<List<String>> rows) => Uint8List.fromList(utf8.encode(toCsv(rows)));
