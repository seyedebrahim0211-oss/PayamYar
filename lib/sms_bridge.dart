import 'dart:io';
import 'package:flutter/services.dart';
import 'message_logic.dart';

class SmsPermissionState {
  final bool canRead;
  final bool canSend;
  const SmsPermissionState({required this.canRead, required this.canSend});
}

class SmsBridge {
  static const MethodChannel _channel = MethodChannel('ir.honarmardomi.payamyar/sms');
  static bool get supported => Platform.isAndroid;

  static Future<bool> available() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('isAvailable') ?? false;
  }

  static Future<SmsPermissionState> status() async {
    if (!supported) return const SmsPermissionState(canRead: false, canSend: false);
    final raw = await _channel.invokeMapMethod<String, bool>('permissionStatus') ?? {};
    return SmsPermissionState(canRead: raw['read'] ?? false, canSend: raw['send'] ?? false);
  }

  static Future<void> request() async {
    if (supported) await _channel.invokeMethod<void>('requestPermissions');
  }

  static Future<List<MessageRecord>> read({int limit = 250}) async {
    if (!supported) return [];
    final response = await _channel.invokeListMethod<dynamic>('readMessages', {'limit': limit});
    return (response ?? []).map((value) {
      final row = Map<Object?, Object?>.from(value as Map);
      return MessageRecord(
        sender: row['sender']?.toString() ?? '',
        body: row['body']?.toString() ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((row['date'] as num).toInt()),
        outgoing: row['outgoing'] == true,
      );
    }).toList();
  }

  static String normalizeNumber(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    return value.split('').map((c) {
      final p = persian.indexOf(c);
      if (p >= 0) return p.toString();
      final a = arabic.indexOf(c);
      return a >= 0 ? a.toString() : c;
    }).join();
  }

  static Future<String> sendStatus(String requestId) async {
    if (!supported) return 'unsupported';
    return await _channel.invokeMethod<String>('sendStatus', {
      'requestId': requestId,
    }) ?? 'unknown';
  }

  /// Returns Android's request identifier, not confirmation of delivery.
  static Future<String> send(String to, String body) async {
    if (!supported) throw UnsupportedError('Sending requires Android');
    return await _channel.invokeMethod<String>('sendSms', {
      'to': normalizeNumber(to), 'body': body,
    }) ?? '';
  }
}
