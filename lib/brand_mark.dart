import 'package:flutter/material.dart';

/// Compact emblem: message bubble and golden feather, inspired by Iranian motifs.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24), painter: _BrandPainter());
}
class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bubble = Paint()..color = Colors.white..style = PaintingStyle.stroke
      ..strokeWidth = 1.9..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round;
    final feather = Paint()..color = const Color(0xFFFFD687)
      ..style = PaintingStyle.stroke..strokeWidth = 2.3..strokeCap = StrokeCap.round;
    final p = Path()..moveTo(3, 6)..quadraticBezierTo(3, 3, 6, 3)
      ..lineTo(17, 3)..quadraticBezierTo(20, 3, 20, 6)
      ..lineTo(20, 14)..quadraticBezierTo(20, 17, 17, 17)
      ..lineTo(10, 17)..lineTo(6, 21)..lineTo(6, 17)
      ..quadraticBezierTo(3, 17, 3, 14)..close();
    canvas.drawPath(p, bubble);
    canvas.drawLine(const Offset(9, 14), const Offset(20, 4), feather);
    final quill = Path()..moveTo(20, 4)..quadraticBezierTo(12, 4, 11, 11)
      ..quadraticBezierTo(18, 10, 20, 4);
    canvas.drawPath(quill, feather);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
