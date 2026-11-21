import 'package:flutter/material.dart';
import 'design/tokens.dart';

/// Compact speech emblem shared with Android's vector launcher icon.
/// No tiny Persian text or detached decorative dot at small icon sizes.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .23),
    child: Container(
      width: size, height: size,
      color: const Color(0xFF01383F),
      padding: EdgeInsets.all(size * .09),
      child: CustomPaint(painter: const _PayamSymbolPainter()),
    ),
  );
}

class _PayamSymbolPainter extends CustomPainter {
  const _PayamSymbolPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    final speech = Path()
      ..moveTo(31, 26)
      ..cubicTo(25, 26, 21, 30, 21, 36)
      ..lineTo(21, 63)
      ..cubicTo(21, 69, 25, 73, 31, 73)
      ..lineTo(35, 73)
      ..lineTo(35, 85)
      ..lineTo(49, 73)
      ..lineTo(77, 73)
      ..cubicTo(83, 73, 87, 69, 87, 63)
      ..lineTo(87, 36)
      ..cubicTo(87, 30, 83, 26, 77, 26)
      ..close();
    canvas.drawPath(speech, Paint()..color = const Color(0xFFFFF9EC));
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(36, 40, 36, 6), const Radius.circular(2)),
      Paint()..color = const Color(0xFF087773));
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(36, 53, 25, 6), const Radius.circular(2)),
      Paint()..color = const Color(0xFF087773));
    final accent = Path()
      ..moveTo(72, 52)..lineTo(78, 58)..lineTo(72, 64)
      ..lineTo(66, 58)..close();
    canvas.drawPath(accent, Paint()..color = const Color(0xFFC9A56A));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PayamSymbolPainter oldDelegate) => false;
}

/// Brand colours shared by the logotype, icons and website.
///
/// This is a thin view over [SColor] so the whole app has a single palette.
/// [gold] stays the decorative gold (never text); [goldInk] is the readable one.
class BrandColors {
  static const teal = SColor.teal;
  static const tealLight = SColor.tealBright;
  static const tealDeep = SColor.tealDeep;
  static const gold = SColor.gold;
  static const goldDeep = SColor.goldInk;
  static const paper = SColor.paper;
}

/// The emblem on its rounded teal tile, as on the launcher icon.
class BrandTile extends StatelessWidget {
  final double size;
  const BrandTile({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => BrandMark(size: size);
}

/// PayamYar logotype: emblem tile + heavy Vazirmatn wordmark «پیام‌یار» whose final
/// stroke carries the gold sparkle, with an optional tagline.
class PayamYarLogotype extends StatelessWidget {
  final double height;
  final bool tagline;
  final Color? color;
  const PayamYarLogotype({super.key, this.height = 44, this.tagline = false, this.color});

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    final word = Text('پیام‌یار', textDirection: TextDirection.rtl,
      style: TextStyle(fontFamily: 'Vazirmatn', fontSize: height * .62, fontWeight: FontWeight.w900,
        height: 1.1, letterSpacing: 0, color: ink));
    return Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
      BrandTile(size: height),
      SizedBox(width: height * .26),
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        word,
        if (tagline)
          Text('پیام‌رسان هوشمند فارسی', style: TextStyle(fontFamily: 'Vazirmatn', fontSize: height * .24,
            fontWeight: FontWeight.w600, height: 1.4, color: ink.withValues(alpha: .62))),
      ]),
    ]);
  }
}
