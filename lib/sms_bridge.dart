import 'dart:io';
import 'package:flutter/services.dart';
import 'message_logic.dart';

class SmsPermissionState {
  final bool isDefault;
  final bool canRead;
  final bool canSend;
  const SmsPermissionState({required this.canRead, required this.canSend, this.isDefault = false});
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
    return SmsPermissionState(canRead: raw['read'] ?? false, canSend: raw['send'] ?? false, isDefault: raw['default'] ?? false);
  }

  static Future<void> request() async {
    if (supported) await _channel.invokeMethod<void>('requestPermissions');
  }

  static Future<List<MessageRecord>> read({int limit = 500, MessageRecord? before}) async {
    if (!supported) return [];
    final response = await _channel.invokeListMethod<dynamic>('readMessages', {'limit': limit, 'beforeDate': before?.date.millisecondsSinceEpoch, 'beforeId': before?.id});
    return (response ?? []).map((value) {
      final row = Map<Object?, Object?>.from(value as Map);
      return MessageRecord(
        id: (row['id'] as num).toInt(), read: row['read'] == true,
        type: (row['type'] as num?)?.toInt() ?? 1, delivery: (row['delivery'] as num?)?.toInt() ?? -1,
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

  static void listen(Future<void> Function(String) callback) {
    _channel.setMethodCallHandler((call) => callback(call.method));
  }
  static void stopListening() => _channel.setMethodCallHandler(null);
  static Future<void> requestDefault() => _channel.invokeMethod<void>('requestDefault');
  static Future<List<Map<dynamic, dynamic>>> subscriptions() async =>
    (await _channel.invokeListMethod<dynamic>('subscriptions') ?? []).map((e) => Map<dynamic, dynamic>.from(e as Map)).toList();
  static Future<Map<String, dynamic>?> composeIntent() => _channel.invokeMapMethod<String, dynamic>('takeComposeIntent');
  static Future<String> queue(String to, String body, int sim) async =>
    await _channel.invokeMethod<String>('queueSms', {'to': normalizeNumber(to), 'body': body, 'subscriptionId': sim}) ?? '';
  static Future<bool> cancel(String id) async =>
    await _channel.invokeMethod<bool>('cancelSms', {'requestId': id}) ?? false;
  static Future<void> markRead(List<int> ids) async {
    for (var start = 0; start < ids.length; start += 500) {
      await _channel.invokeMethod<void>('markRead', {'ids': ids.sublist(start, (start + 500).clamp(0, ids.length))});
    }
  }
  static Future<void> delete(List<int> ids) => _channel.invokeMethod<void>('deleteMessages', {'ids': ids});
}
