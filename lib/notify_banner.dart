import 'package:flutter/foundation.dart';

/// A new message shown as the glass banner while PayamYar is on screen.
class IncomingBanner {
  final String address;
  final String name;
  final String body;
  final DateTime time;
  final String? otp;
  final bool canReply;

  /// Settings preview: nothing is opened or sent.
  final bool sample;

  const IncomingBanner({required this.address, required this.name, required this.body, required this.time,
      this.otp, this.canReply = false, this.sample = false});

  /// Payload of the native "incomingBanner" event (see Notifier.kt).
  static IncomingBanner? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final address = raw['address']?.toString() ?? '';
    if (address.isEmpty) return null;
    final millis = (raw['time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final otp = raw['otp']?.toString();
    return IncomingBanner(
      address: address,
      name: raw['name']?.toString() ?? address,
      body: raw['body']?.toString() ?? '',
      time: DateTime.fromMillisecondsSinceEpoch(millis),
      otp: (otp == null || otp.isEmpty) ? null : otp,
      canReply: raw['canReply'] == true,
    );
  }

  static IncomingBanner preview() => IncomingBanner(
        address: 'preview',
        name: 'پیامیار',
        body: 'سلام! این نمونه اعلان شیشه‌ای پیامیار است. کد آزمایشی: 12345',
        time: DateTime.now(),
        otp: '12345',
        canReply: true,
        sample: true,
      );
}

/// The banner currently on screen (null when none). Written by AppStore and the settings preview.
final ValueNotifier<IncomingBanner?> currentBanner = ValueNotifier<IncomingBanner?>(null);
