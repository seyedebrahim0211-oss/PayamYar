import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact and expanded notification views preserve native glass contract', () {
    for (final name in ['payamyar_notification_glass.xml',
      'payamyar_notification_expanded.xml']) {
      final xml = File('android/app/src/main/res/layout/$name').readAsStringSync();
      for (final id in ['glass_frame', 'glass_backdrop', 'glass_avatar',
        'glass_sender', 'glass_meta', 'glass_clock', 'glass_preview', 'glass_code']) {
        expect(xml, contains('@+id/$id'), reason: '$name missing $id');
      }
      expect(xml, contains('android:layoutDirection="rtl"'));
      expect(xml, contains('android:maxLines="'));
    }
  });

  test('native heads-up uses compact view, expanded shade retains full layout', () {
    final source = File(
      'android/app/src/main/kotlin/ir/honarmardomi/payamyar/Notifier.kt'
    ).readAsStringSync();
    expect(source, contains('builder.setCustomHeadsUpContentView(compact)'));
    expect(source, contains('builder.setCustomBigContentView(expanded)'));
    expect(source, contains('view.setImageViewBitmap(R.id.glass_avatar, avatar)'));
    expect(source, contains('view.setImageViewBitmap(R.id.glass_backdrop, glassBackdrop(c, expanded))'));
    expect(source, contains('view.setOnClickPendingIntent(R.id.glass_code'));
    expect(source, contains('if (!sample) openIntent.setAction'));
    expect(source, isNot(contains('text.take(115)')));
  });

  test('preview bridge confirms that system notification was really permitted', () {
    final flutterBridge = File('lib/sms_bridge.dart').readAsStringSync();
    final native = File(
      'android/app/src/main/kotlin/ir/honarmardomi/payamyar/MainActivity.kt'
    ).readAsStringSync();
    expect(flutterBridge, contains('Future<bool> previewNotification()'));
    expect(native, contains('result.success(Notifier.preview(this))'));
    final screen = File('lib/screens/notification_style_screen.dart').readAsStringSync();
    expect(screen, contains("if (currentBanner.value?.sample == true) currentBanner.value = null;"));
  });
}
