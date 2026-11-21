import 'package:flutter/material.dart';
import 'design/tokens.dart';

/// Approved wagtail mark with breathing room around the silhouette.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Container(width: size, height: size, color: const Color(0xFF011437),
      padding: EdgeInsets.all(size * .085), child: Image.asset('assets/susolang.png')),
  );
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
