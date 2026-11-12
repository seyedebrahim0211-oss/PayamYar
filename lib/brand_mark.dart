import 'dart:math' as math;
import 'package:flutter/material.dart';

/// PayamYar emblem: a white message bubble holding an eight-point star (shamseh), with a gold sparkle.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const _BrandPainter());
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final bubble = Path()
      ..moveTo(6.5, 4)
      ..lineTo(17.5, 4)
      ..quadraticBezierTo(21, 4, 21, 7.5)
      ..lineTo(21, 13.5)
      ..quadraticBezierTo(21, 17, 17.5, 17)
      ..lineTo(16.5, 17)
      ..lineTo(13.2, 21)
      ..lineTo(12.8, 17)
      ..lineTo(6.5, 17)
      ..quadraticBezierTo(3, 17, 3, 13.5)
      ..lineTo(3, 7.5)
      ..quadraticBezierTo(3, 4, 6.5, 4)
      ..close();
    canvas.drawPath(bubble, Paint()..color = Colors.white);
    final star = Path();
    for (var k = 0; k < 16; k++) {
      final r = k.isOdd ? 3.1 : 4.3;
      final a = (k * 22.5 - 90) * math.pi / 180;
      final p = Offset(12 + r * math.cos(a), 10.5 + r * math.sin(a));
      if (k == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = const Color(0xFF087F81));
    canvas.drawCircle(const Offset(12, 10.5), 1.2, Paint()..color = Colors.white);
    final sparkle = Path()
      ..moveTo(20.5, 0.5)
      ..quadraticBezierTo(20.9, 3.6, 24, 4)
      ..quadraticBezierTo(20.9, 4.4, 20.5, 7.5)
      ..quadraticBezierTo(20.1, 4.4, 17, 4)
      ..quadraticBezierTo(20.1, 3.6, 20.5, 0.5)
      ..close();
    canvas.drawPath(sparkle, Paint()..color = const Color(0xFFFFD27A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Brand colours shared by the logotype, icons and website.
class BrandColors {
  static const teal = Color(0xFF087F81);
  static const tealLight = Color(0xFF12A7A2);
  static const tealDeep = Color(0xFF05545A);
  static const gold = Color(0xFFFFD27A);
  static const goldDeep = Color(0xFFB8862B);
  static const paper = Color(0xFFFAF8F3);
}

/// The emblem on its rounded teal tile, as on the launcher icon.
class BrandTile extends StatelessWidget {
  final double size;
  const BrandTile({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    padding: EdgeInsets.all(size * .2),
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
        colors: [BrandColors.tealLight, BrandColors.teal, BrandColors.tealDeep]),
      borderRadius: BorderRadius.circular(size * .32),
      boxShadow: [BoxShadow(color: BrandColors.tealDeep.withValues(alpha: .25), blurRadius: size * .3, offset: Offset(0, size * .1))],
    ),
    child: BrandMark(size: size * .6),
  );
}

/// PayamYar logotype: emblem tile + heavy Vazirmatn wordmark «پیامیار» whose final
/// stroke carries the gold sparkle, with an optional tagline.
class PayamYarLogotype extends StatelessWidget {
  final double height;
  final bool tagline;
  final Color? color;
  const PayamYarLogotype({super.key, this.height = 44, this.tagline = false, this.color});

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    final word = Text('پیامیار', textDirection: TextDirection.rtl,
      style: TextStyle(fontFamily: 'Vazirmatn', fontSize: height * .62, fontWeight: FontWeight.w900,
        height: 1.1, letterSpacing: 0, color: ink));
    return Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
      BrandTile(size: height),
      SizedBox(width: height * .26),
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(clipBehavior: Clip.none, children: [
          word,
          // Gold sparkle above the opening «پ», echoing the emblem.
          Positioned(right: -height * .08, top: -height * .06,
            child: CustomPaint(size: Size.square(height * .26), painter: const _SparklePainter())),
        ]),
        if (tagline)
          Text('پیام‌رسان هوشمند فارسی', style: TextStyle(fontFamily: 'Vazirmatn', fontSize: height * .24,
            fontWeight: FontWeight.w600, height: 1.4, color: ink.withValues(alpha: .62))),
      ]),
    ]);
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, c = w / 2;
    final p = Path()
      ..moveTo(c, 0)
      ..quadraticBezierTo(c + w * .06, c - w * .06, w, c)
      ..quadraticBezierTo(c + w * .06, c + w * .06, c, w)
      ..quadraticBezierTo(c - w * .06, c + w * .06, 0, c)
      ..quadraticBezierTo(c - w * .06, c - w * .06, c, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = BrandColors.gold);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
