import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Match only the SMS sender, never message text or the user's contact label.
class BankBadge extends StatelessWidget {
  const BankBadge({super.key, required this.sender, required this.size,
    required this.fallback, this.square = false});
  final String sender;
  final double size;
  final bool square;
  final Widget fallback;

  static final _separators = RegExp(r'[\s._‌-]');
  static String senderKey(String value) => value.toLowerCase().replaceAll(_separators, '')
      .replaceAll('ك', 'ک').replaceAll('ي', 'ی');
  static final _catalog = rootBundle.loadString('assets/banks/senders.json')
      .then((raw) => Map<String, String>.from(jsonDecode(raw) as Map));

  @override
  Widget build(BuildContext context) {
    final key = senderKey(sender);
    if (key.isEmpty || key.startsWith('+') || key.startsWith('09')) return fallback;
    return FutureBuilder<Map<String, String>>(
      future: _catalog,
      builder: (context, snapshot) {
        final bank = snapshot.data?[key];
        if (bank == null) return fallback;
        return Container(
          width: size, height: size, padding: EdgeInsets.all(size * .12),
          decoration: BoxDecoration(color: Colors.white,
            border: Border.all(color: const Color(0x28000000)),
            borderRadius: BorderRadius.circular(size * (square ? .28 : .5))),
          child: Image.asset('assets/banks/$bank.png', fit: BoxFit.contain,
            excludeFromSemantics: true),
        );
      },
    );
  }
}
