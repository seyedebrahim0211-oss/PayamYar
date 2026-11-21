import 'dart:typed_data';
import 'chat_image_frame.dart';
import '../chat_personalization.dart';
import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../message_logic.dart';
import '../bank_badge.dart';
import '../sms_bridge.dart';

/// آواتار فرستنده: حرف اول برای افراد، آیکن برای بانک/خدمات/تبلیغات.
/// شکلش مربع نرم است (نه دایره) تا با نشان برنامه هم‌خانواده باشد.
class SenderAvatar extends StatelessWidget {
  final String name;
  final String address;
  final MessageCategory category;
  final double radius;
  const SenderAvatar({super.key, required this.name, required this.address, required this.category, this.radius = 25});

  static final Map<String, Future<Uint8List?>> _photoCache = {};

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ChatPersonalizations.instance,
    builder: (context, _) => _avatar(context),
  );

  Widget _avatar(BuildContext context) {
    final person = name != address || RegExp(r'^\+?[\d\s۰-۹]{7,}$').hasMatch(address);
    Widget child;
    if (category == MessageCategory.personal && person && name.isNotEmpty && name != address) {
      child = Text(name.characters.first, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * .8));
    } else {
      final icon = switch (category) {
        MessageCategory.banking => Icons.account_balance_rounded,
        MessageCategory.service => Icons.support_agent_rounded,
        MessageCategory.advertising => Icons.campaign_rounded,
        MessageCategory.personal => person ? Icons.person_rounded : Icons.business_rounded,
      };
      child = Icon(icon, color: Colors.white, size: radius * .95);
    }
    final fallback = BankBadge(sender: address, size: radius * 2,
        square: true, fallback: SoftAvatar(seed: address, size: radius * 2,
          color: switch (category) {
            MessageCategory.banking => const Color(0xFF22694F),
            MessageCategory.service => const Color(0xFF315F92),
            MessageCategory.advertising => const Color(0xFF99522E),
            MessageCategory.personal => null,
          }, child: child));
    // An explicit per-chat avatar has priority over the phone-book picture,
    // bank logo and letter fallback, and is read only from private app storage.
    final room = ChatPersonalizations.instance.forAddress(address);
    final chosen = room.avatarPath;
    if (chosen != null) {
      final pixels = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius * .68),
        child: SizedBox.square(dimension: radius * 2,
          child: FramedChatImage(chosen, room.avatarFrame, pixels: (pixels * 3).clamp(96, 768),
            fallback: fallback)),
      );
    }
    final phone = SmsBridge.normalizeNumber(address).replaceAll(RegExp(r'[^0-9]'), '');
    if (!SmsBridge.supported || category != MessageCategory.personal || phone.length < 7) {
      return fallback;
    }
    if (_photoCache.length > 400) _photoCache.remove(_photoCache.keys.first);
    final picture = _photoCache.putIfAbsent(address, () => SmsBridge.contactPhoto(address));
    return FutureBuilder<Uint8List?>(
      future: picture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return fallback;
        // Decode at the size actually drawn: without cacheWidth the full-size contact photo
        // was decoded again for every row on every rebuild (a real cost on long inboxes).
        final pixels = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius * .68),
          child: Image.memory(bytes,
              width: radius * 2, height: radius * 2, fit: BoxFit.cover,
              cacheWidth: pixels.clamp(48, 512),
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => fallback),
        );
      },
    );
  }
}

/// آواتار مربع نرم با هایلایت شیشه‌ای — هم‌خانوادهٔ نشان لانچر.
///
/// جای دایرهٔ تخت قبلی را می‌گیرد. شعاع ۳۴٪ همان نسبتی است که در آیکن برنامه
/// استفاده شده، و هایلایت بالا با تم «شیشه‌ای» گفتگو یکی می‌شود.
class SoftAvatar extends StatelessWidget {
  final String seed;
  final double size;
  final Widget child;
  final Color? color;

  const SoftAvatar({super.key, required this.seed, required this.size, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    // `hashCode.abs()` stays negative for the single value -2^63 and would produce a
    // negative index; masking the sign bit is always safe.
    final base = color ?? SColor.avatar[(seed.hashCode & 0x7FFFFFFF) % SColor.avatar.length];
    final radius = size * .34;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color.lerp(base, Colors.white, .18)!, base, Color.lerp(base, Colors.black, .18)!],
          stops: const [0, .55, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: child),
          // هایلایت شیشه: نیمهٔ بالایی، محو به پایین.
          Positioned(
            top: 0, left: 0, right: 0, height: size * .46,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: .3), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String categoryName(MessageCategory? c) => switch (c) {
  null => 'همه',
  MessageCategory.personal => 'شخصی',
  MessageCategory.banking => 'بانکی',
  MessageCategory.service => 'خدماتی',
  MessageCategory.advertising => 'تبلیغاتی',
};

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  /// دکمهٔ اقدام؛ حالت خالی باید دعوت به کار باشد، نه بن‌بست.
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle,
      this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SSpace.xxl, vertical: 56),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 76, height: 76,
          decoration: BoxDecoration(
            borderRadius: SRadius.all(26),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                scheme.primary.withValues(alpha: .14),
                SColor.gold.withValues(alpha: .22),
              ],
            ),
          ),
          child: Icon(icon, size: 34, color: scheme.primary),
        ),
        const SizedBox(height: SSpace.lg),
        Text(title, textAlign: TextAlign.center,
          style: TextStyle(fontSize: SType.h3, fontWeight: FontWeight.w800, color: scheme.onSurface)),
        if (subtitle != null) ...[
          const SizedBox(height: SSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(subtitle!, textAlign: TextAlign.center,
              style: TextStyle(fontSize: SType.small, height: 1.75, color: scheme.onSurfaceVariant)),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: SSpace.xl),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.field)),
            ),
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(actionLabel!),
          ),
        ],
      ]),
    );
  }
}
