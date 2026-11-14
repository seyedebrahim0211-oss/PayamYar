import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/sms_bridge.dart';

void main() {
  test('malformed native SMS pages are rejected safely', () {
    expect(SmsBridge.fromColumns(null), isEmpty);
    expect(SmsBridge.fromColumns({'n': 100000}), isEmpty);
    expect(SmsBridge.fromColumns({
      'n': 2, 'ids': [1], 'dates': [1], 'types': [1],
      'reads': [1], 'status': [0], 'senders': ['a'], 'bodies': ['x'],
    }), isEmpty);
  });

  test('only valid SMS rows survive native decoding', () {
    final records = SmsBridge.fromColumns({
      'n': 2,
      'ids': [11, 'malformed'],
      'dates': [1760000000000, 1760000000000],
      'types': [1, 1],
      'reads': [0, 1],
      'status': [-1, -1],
      'senders': ['09123456789', 'bad'],
      'bodies': ['سلام', 'ignored'],
    });
    expect(records, hasLength(1));
    expect(records.single.id, 11);
    expect(records.single.body, 'سلام');
    expect(records.single.read, isFalse);
  });
}
