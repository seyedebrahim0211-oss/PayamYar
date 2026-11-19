import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/app_settings.dart';
import 'package:payamyar/screens/glass_banner.dart';
import 'package:payamyar/screens/notification_style_screen.dart';

void main() {
  testWidgets('settings displays the complete compact card and its RTL copy action', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(392, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() async {
      final fonts = FontLoader('Vazirmatn')..addFont(rootBundle.load('assets/fonts/Vazirmatn.ttf'));
      final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([fonts.load(), icons.load()]);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Vazirmatn'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: NotificationStyleScreen(settings: AppSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('notification-style-preview'));
    final card = find.descendant(of: preview, matching: find.byType(GlassBannerCard));
    final copy = find.descendant(of: card, matching: find.text('کپی کد'));
    expect(copy, findsOneWidget);
    expect(tester.getRect(card).contains(tester.getCenter(copy)), isTrue);
    expect(tester.getCenter(copy).dx, greaterThan(tester.getCenter(card).dx));
    expect(tester.takeException(), isNull);

    // CI attaches the production widget with synthetic sample data for visual review.
    final directory = Platform.environment['PAYAMYAR_PREVIEW_DIR'];
    if (directory != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(preview);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/PayamYar-Glass-Preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  });
}
