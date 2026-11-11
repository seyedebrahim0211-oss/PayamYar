import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payamyar/app_store.dart';
import 'package:payamyar/main.dart';
import 'package:payamyar/sms_bridge.dart';
import 'package:payamyar/text_polish.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('text editor', () {
    test('fixes half-spaces, Arabic letters and punctuation', () {
      expect(TextPolish.orthography('من می خواهم كتاب ها را ببينم ,باشه'), 'من می‌خواهم کتاب‌ها را ببینم، باشه');
      expect(TextPolish.orthography('میکنم'), 'می‌کنم');
      expect(TextPolish.orthography('سلام   خوبی ؟؟'), 'سلام خوبی؟');
    });
    test('keeps phone numbers and links, converts small numbers', () {
      expect(TextPolish.orthography('ساعت 10 بیا'), 'ساعت ۱۰ بیا');
      expect(TextPolish.orthography('شماره 09121234567 است'), 'شماره 09121234567 است');
      expect(TextPolish.orthography('لینک https://a.ir/p1 را ببین'), 'لینک https://a.ir/p1 را ببین');
    });
    test('spelling and formal tone', () {
      expect(TextPolish.spelling('لطفا راجب جلسه خبر بده'), 'لطفاً راجع به جلسه خبر بده');
      expect(TextPolish.formal('اگه میتونی بهم بگو'), 'اگر می‌توانی به من بگو');
      expect(TextPolish.apply('نمیدونم', formalTone: true), 'نمی‌دانم');
    });
    test('does not touch words that only contain a dictionary entry', () {
      expect(TextPolish.formal('دیگهای'), 'دیگهای');
      expect(TextPolish.spelling('حتماً'), 'حتماً');
    });
    test('polite adds greeting and closing once', () {
      final once = TextPolish.polite('فایل را بفرستید');
      expect(once, 'سلام، وقت بخیر.\nفایل را بفرستید\nبا تشکر');
      expect(TextPolish.polite(once), once);
    });
    test('SMS part counter', () {
      expect(TextPolish.smsParts('سلام').parts, 1);
      expect(TextPolish.smsParts('س' * 70).parts, 1);
      expect(TextPolish.smsParts('س' * 71).parts, 2);
      expect(TextPolish.smsParts('a' * 160).parts, 1);
      expect(TextPolish.smsParts('a' * 161).parts, 2);
    });
  });

  test('native columns are decoded into messages', () {
    final rows = SmsBridge.fromColumns({
      'n': 2,
      'ids': Int64List.fromList([7, 6]),
      'dates': Int64List.fromList([2000, 1000]),
      'types': Int32List.fromList([1, 2]),
      'reads': Int32List.fromList([0, 1]),
      'status': Int32List.fromList([-1, 0]),
      'senders': ['+989121234567', null],
      'bodies': ['سلام', 'جواب'],
    });
    expect(rows.length, 2);
    expect(rows[0].id, 7);
    expect(rows[0].read, isFalse);
    expect(rows[0].outgoing, isFalse);
    expect(rows[1].outgoing, isTrue);
    expect(rows[1].sender, '');
    expect(rows[1].delivery, 0);
  });

  test('pinning moves a conversation to the top and survives regrouping', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.init();
    expect(store.visible(archive: false).first.address, 'هنر مردمی');
    store.togglePin('فروشگاه');
    expect(store.visible(archive: false).first.address, 'فروشگاه');
    expect(store.unreadConversations, 1);
    await store.markRead(store.conversationFor('هنر مردمی')!);
    expect(store.unreadConversations, 0);
    expect(store.visible(archive: false).first.address, 'فروشگاه');
    store.togglePin('فروشگاه');
    expect(store.visible(archive: false).first.address, 'هنر مردمی');
    final id = store.conversationFor('بانک')!.latest.id!;
    store.togglePinMessage('بانک', id);
    expect(store.pinnedMessageId('بانک'), id);
    await store.deleteMessages([id]);
    expect(store.pinnedMessageId('بانک'), isNull);
    expect(store.conversationFor('بانک'), isNull);
    store.dispose();
  });

  testWidgets('long-press menu pins a conversation to the top', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('فروشگاه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سنجاق کردن بالای فهرست'));
    await tester.pumpAndSettle();
    final shop = tester.getTopLeft(find.text('فروشگاه')).dy;
    final first = tester.getTopLeft(find.text('هنر مردمی')).dy;
    expect(shop, lessThan(first));
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
  });

  testWidgets('Conversation has a right-hand hold-to-schedule send control', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.tap(find.text('09121234567'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('ارسال (لمس طولانی: ارسال زمان‌دار)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'یادآوری');
    await tester.pump();
    await tester.longPress(find.byTooltip('ارسال (لمس طولانی: ارسال زمان‌دار)'));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب روز ارسال'), findsWidgets);
  });

  testWidgets('Message composer exposes up to 500 recipients', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.tap(find.text('پیام جدید'));
    await tester.pumpAndSettle();
    expect(find.text('0 از 500'), findsOneWidget);
  });

  testWidgets('text editor sheet rewrites the reply box', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PayamYar());
    await tester.pumpAndSettle();
    await tester.tap(find.text('09121234567'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'من می خواهم بیام');
    await tester.pump();
    await tester.tap(find.byTooltip('ابزارهای پیام'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش متن'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('جایگزینی با متن نهایی'));
    await tester.pumpAndSettle();
    expect(find.text('من می‌خواهم بیام'), findsOneWidget);
  });
}
