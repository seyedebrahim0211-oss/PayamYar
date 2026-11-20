import 'package:flutter/material.dart';

/// PayamYar emblem: a white message bubble holding an eight-point star (shamseh), with a gold sparkle.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Image.asset('assets/susolang.png', width: size, height: size),
  );
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
  Widget build(BuildContext context) => BrandMark(size: size);
}

/// PayamYar logotype: emblem tile + heavy Vazirmatn wordmark «سوسلنگ» whose final
/// stroke carries the gold sparkle, with an optional tagline.
class PayamYarLogotype extends StatelessWidget {
  final double height;
  final bool tagline;
  final Color? color;
  const PayamYarLogotype({super.key, this.height = 44, this.tagline = false, this.color});

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    final word = Text('سوسلنگ', textDirection: TextDirection.rtl,
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
