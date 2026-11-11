import 'package:flutter/material.dart';
import '../message_logic.dart';

const _avatarColors = [
  Color(0xFF087F81), Color(0xFF305F91), Color(0xFF75539A), Color(0xFF9F5369),
  Color(0xFF47765F), Color(0xFFA17A37), Color(0xFFC0583B), Color(0xFF3A7CA5),
];

/// Round avatar: first letter for people, an icon for banks/services/ads and short codes.
class SenderAvatar extends StatelessWidget {
  final String name;
  final String address;
  final MessageCategory category;
  final double radius;
  const SenderAvatar({super.key, required this.name, required this.address, required this.category, this.radius = 25});

  @override
  Widget build(BuildContext context) {
    final color = _avatarColors[address.hashCode.abs() % _avatarColors.length];
    final person = name != address || RegExp(r'^\+?[\d\s۰-۹]{7,}$').hasMatch(address);
    Widget child;
    if (category == MessageCategory.personal && person && name != address) {
      child = Text(name.characters.first, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * .8));
    } else {
      final icon = switch (category) {
        MessageCategory.banking => Icons.account_balance_rounded,
        MessageCategory.service => Icons.verified_user_rounded,
        MessageCategory.advertising => Icons.campaign_rounded,
        MessageCategory.personal => person ? Icons.person_rounded : Icons.business_rounded,
      };
      child = Icon(icon, color: Colors.white, size: radius * .95);
    }
    return CircleAvatar(radius: radius, backgroundColor: color, child: child);
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
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 40, backgroundColor: scheme.primaryContainer,
          child: Icon(icon, size: 38, color: scheme.onPrimaryContainer)),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ]),
    );
  }
}
