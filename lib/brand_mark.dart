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
