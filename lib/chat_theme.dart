import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_settings.dart';

/// Visual recipe for one chat look: background, bubbles and composer.
class ChatLook {
  final Decoration background;
  final CustomPainter? pattern;
  final BoxDecoration Function(bool outgoing, bool failed) bubble;
  final Color Function(bool outgoing, bool failed) ink;
  final double radius;
  final BoxDecoration composer;
  final BoxDecoration dayChip;
  final Color dayInk;
  const ChatLook({required this.background, this.pattern, required this.bubble, required this.ink,
    required this.radius, required this.composer, required this.dayChip, required this.dayInk});

  static ChatLook of(ChatStyle style, ColorScheme s) {
    final dark = s.brightness == Brightness.dark;
    switch (style) {
      case ChatStyle.traditional:
        const gold = Color(0xFFC9A45C);
        return ChatLook(
          background: BoxDecoration(color: dark ? const Color(0xFF13211F) : const Color(0xFFF5EEDF)),
          pattern: GirihPainter(color: (dark ? const Color(0xFFC9A45C) : const Color(0xFF8A6A2C)).withValues(alpha: dark ? .07 : .08)),
          radius: 18,
          bubble: (out, failed) => BoxDecoration(
            gradient: failed ? null : out
                ? LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
                    colors: dark ? const [Color(0xFF136B6A), Color(0xFF0C4A4C)] : const [Color(0xFF0E8483), Color(0xFF0A5F63)])
                : null,
            color: failed ? s.errorContainer : out ? null : (dark ? const Color(0xFF22302C) : const Color(0xFFFFFCF4)),
            border: Border.all(color: gold.withValues(alpha: out ? .55 : .45), width: 1),
            boxShadow: [BoxShadow(color: const Color(0xFF5A4520).withValues(alpha: .08), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          ink: (out, failed) => failed ? s.onErrorContainer : out ? Colors.white : (dark ? const Color(0xFFF2E9D6) : const Color(0xFF2B2416)),
          composer: BoxDecoration(
            color: dark ? const Color(0xFF1B2A27) : const Color(0xFFFFFCF4),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: gold.withValues(alpha: .7), width: 1.2)),
          dayChip: BoxDecoration(
            color: dark ? const Color(0xFF2A3A35) : const Color(0xFFFBF3E2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gold.withValues(alpha: .6))),
          dayInk: dark ? const Color(0xFFE7D3A6) : const Color(0xFF7A5B22),
        );
      case ChatStyle.glass:
        return ChatLook(
          background: BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
            colors: dark
                ? const [Color(0xFF0C2B33), Color(0xFF1C2140), Color(0xFF2A1C33)]
                : [s.primary.withValues(alpha: .28), const Color(0xFFE9E4FA), const Color(0xFFFCE7D4)])),
          pattern: BlobPainter(dark: dark, tint: s.primary),
          radius: 22,
          bubble: (out, failed) => BoxDecoration(
            color: failed ? s.errorContainer.withValues(alpha: .85)
                : out ? s.primary.withValues(alpha: dark ? .45 : .62)
                : Colors.white.withValues(alpha: dark ? .10 : .58),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? .18 : .75), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          ink: (out, failed) => failed ? s.onErrorContainer : out ? Colors.white : (dark ? Colors.white : const Color(0xFF1D2433)),
          composer: BoxDecoration(
            color: Colors.white.withValues(alpha: dark ? .10 : .7),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? .2 : .9))),
          dayChip: BoxDecoration(color: Colors.white.withValues(alpha: dark ? .12 : .6), borderRadius: BorderRadius.circular(14)),
          dayInk: dark ? Colors.white70 : const Color(0xFF3B4256),
        );
      case ChatStyle.minimal:
        return ChatLook(
          background: BoxDecoration(color: s.surface),
          radius: 14,
          bubble: (out, failed) => BoxDecoration(
            color: failed ? s.errorContainer : out ? s.primary : s.surfaceContainerHigh),
          ink: (out, failed) => failed ? s.onErrorContainer : out ? s.onPrimary : s.onSurface,
          composer: BoxDecoration(color: s.surfaceContainerHigh, borderRadius: BorderRadius.circular(24)),
          dayChip: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
          dayInk: s.onSurfaceVariant,
        );
      case ChatStyle.classic:
        return ChatLook(
          background: BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
            colors: [s.primary.withValues(alpha: .055), s.surfaceContainerLowest, const Color(0xFFD6B779).withValues(alpha: .055)])),
          radius: 20,
          bubble: (out, failed) => BoxDecoration(
            color: failed ? s.errorContainer : out ? (dark ? const Color(0xFF174D4E) : const Color(0xFFD9EFEB))
                : (dark ? const Color(0xFF263A40) : Colors.white),
            boxShadow: [BoxShadow(color: s.shadow.withValues(alpha: .05), blurRadius: 6, offset: const Offset(0, 2))]),
          ink: (out, failed) => failed ? s.onErrorContainer : out && dark ? const Color(0xFFF1F8F6) : s.onSurface,
          composer: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(26),
            border: Border.all(color: s.outlineVariant)),
          dayChip: BoxDecoration(color: s.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          dayInk: s.onSurfaceVariant,
        );
    }
  }
}

/// Faint repeating eight-point star (girih) lattice, the "traditional" wallpaper.
class GirihPainter extends CustomPainter {
  final Color color;
  const GirihPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1;
    const step = 56.0;
    for (var y = 0.0; y < size.height + step; y += step) {
      for (var x = ((y / step).round().isOdd ? step / 2 : 0.0); x < size.width + step; x += step) {
        final star = Path();
        for (var k = 0; k < 16; k++) {
          final r = k.isOdd ? 9.0 : 15.0;
          final a = (k * 22.5 - 90) * math.pi / 180;
          final p = Offset(x + r * math.cos(a), y + r * math.sin(a));
          if (k == 0) {
            star.moveTo(p.dx, p.dy);
          } else {
            star.lineTo(p.dx, p.dy);
          }
        }
        star.close();
        canvas.drawPath(star, paint);
        canvas.drawCircle(Offset(x, y), 3, paint);
      }
    }
  }
  @override
  bool shouldRepaint(covariant GirihPainter old) => old.color != color;
}

/// Soft colour blobs behind the glass bubbles.
class BlobPainter extends CustomPainter {
  final bool dark;
  final Color tint;
  const BlobPainter({required this.dark, required this.tint});
  @override
  void paint(Canvas canvas, Size size) {
    void blob(double fx, double fy, double r, Color c) => canvas.drawCircle(
      Offset(size.width * fx, size.height * fy), r,
      Paint()..color = c..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    blob(.85, .15, 120, tint.withValues(alpha: dark ? .35 : .30));
    blob(.15, .55, 140, const Color(0xFFB39DDB).withValues(alpha: dark ? .25 : .35));
    blob(.7, .9, 130, const Color(0xFFFFCC80).withValues(alpha: dark ? .18 : .35));
  }
  @override
  bool shouldRepaint(covariant BlobPainter old) => old.dark != dark || old.tint != tint;
}

/// Small live preview used by the theme picker in settings.
class ChatStylePreview extends StatelessWidget {
  final ChatStyle style;
  final bool selected;
  final VoidCallback onTap;
  const ChatStylePreview({super.key, required this.style, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final look = ChatLook.of(style, s);
    Widget bubble(bool out, double w) => Align(
      alignment: out ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(width: w, height: 16, margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: look.bubble(out, false).copyWith(borderRadius: BorderRadius.circular(look.radius / 2))));
    return Semantics(
      button: true, selected: selected, label: 'قالب ${chatStyleNames[style]}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 104,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? s.primary : s.outlineVariant, width: selected ? 2.5 : 1)),
          child: Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 112, decoration: look.background,
                child: CustomPaint(
                  painter: look.pattern,
                  child: Padding(padding: const EdgeInsets.all(8), child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [bubble(false, 58), bubble(true, 66), bubble(false, 44), bubble(true, 52)])),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(chatStyleNames[style]!, style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? s.primary : s.onSurface))),
          ]),
        ),
      ),
    );
  }
}
