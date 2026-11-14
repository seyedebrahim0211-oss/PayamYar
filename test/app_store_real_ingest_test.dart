import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/message_logic.dart';

void main() {
  test('actual AppStore ingestion groups senders, counts unread and rebuilds cleanly', () {
    final store = AppStore(android: false);
    final time = DateTime(2026, 11, 14, 13);
    store.ingestForTesting([
      MessageRecord(sender: '+989121234567', body: 'سلام', date: time,
        id: 1, read: false, outgoing: false),
      MessageRecord(sender: '09121234567', body: 'پاسخ', date: time,
        id: 2, read: true, outgoing: true, type: 2),
      MessageRecord(sender: '09123334444', body: 'خوبی؟', date: time,
        id: 3, read: false),
    ]);
    expect(store.conversations.length, 2);
    expect(store.conversationFor('09121234567')?.messages.length, 2);
    expect(store.unreadConversations, 2);
    final generation = store.revision;
    store.ingestForTesting([]);
    expect(store.conversations, isEmpty);
    expect(store.unreadConversations, 0);
    expect(store.revision, greaterThan(generation));
    store.dispose();
  });
}
