import 'dart:io';
import 'package:flutter/services.dart';
import 'message_logic.dart';

class SmsPermissionState {
  final bool isDefault;
  final bool canRead;
  final bool canSend;
  final bool contacts;
  const SmsPermissionState({required this.canRead, required this.canSend, this.isDefault = false, this.contacts = false});
  static SmsPermissionState fromMap(Map<String, bool> raw) => SmsPermissionState(
    canRead: raw['read'] ?? false, canSend: raw['send'] ?? false,
    isDefault: raw['default'] ?? false, contacts: raw['contacts'] ?? false);
}

/// Android "special access" switches that keep background SMS delivery and timing reliable.
class SpecialAccess {
  final bool battery;
  final bool exactAlarm;
  final bool notifications;
  const SpecialAccess({this.battery = true, this.exactAlarm = true, this.notifications = true});
  bool get complete => battery && exactAlarm && notifications;
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
    return SmsPermissionState.fromMap(raw);
  }

  /// Shows the Android permission dialog and completes with the state after the user answers.
  static Future<SmsPermissionState> request() async {
    if (!supported) return const SmsPermissionState(canRead: false, canSend: false);
    final raw = await _channel.invokeMapMethod<String, bool>('requestPermissions') ?? {};
    return SmsPermissionState.fromMap(raw);
  }

  /// Decodes one page sent by the native side as typed columns.
  static List<MessageRecord> fromColumns(Object? raw) {
    if (raw is! Map) return const [];
    final n = (raw['n'] as num?)?.toInt() ?? 0;
    final ids = raw['ids'] as List, dates = raw['dates'] as List, types = raw['types'] as List;
    final reads = raw['reads'] as List, status = raw['status'] as List;
    final senders = raw['senders'] as List, bodies = raw['bodies'] as List;
    return List<MessageRecord>.generate(n, (i) {
      final type = (types[i] as num).toInt();
      return MessageRecord(
        id: (ids[i] as num).toInt(),
        sender: senders[i] as String? ?? '',
        body: bodies[i] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((dates[i] as num).toInt()),
        outgoing: type != 1,
        read: (reads[i] as num) != 0,
        type: type,
        delivery: (status[i] as num).toInt(),
      );
    }, growable: false);
  }

  /// Newest [limit] messages (quick refresh after a change).
  static Future<List<MessageRecord>> read({int limit = 300}) async {
    if (!supported) return [];
    return fromColumns(await _channel.invokeMethod<Object?>('readMessages', {'limit': limit}));
  }

  /// Starts one native pass over the whole inbox. Pages arrive as 'messagesPage' events
  /// (see [listen]) tagged with [generation]; completes with the total count.
  static Future<int> loadAll(int generation) async =>
    await _channel.invokeMethod<int>('loadAllMessages', {'generation': generation}) ?? 0;

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

  static void listen(Future<void> Function(String method, Object? arguments) callback) {
    _channel.setMethodCallHandler((call) => callback(call.method, call.arguments));
  }
  static void stopListening() => _channel.setMethodCallHandler(null);

  /// Downloads the release from honarmardomi.ir and opens Android's installer.
  /// Returns 'installing' or 'needs_permission' (the "install unknown apps" screen was opened).
  static Future<String> installUpdate(String url) async =>
    await _channel.invokeMethod<String>('installUpdate', {'url': url}) ?? 'installing';
  /// Phone-book entries for the in-app multi-select UI. Permission is requested by the caller.
  static Future<List<Map<String, String>>> listContacts() async {
    if (!supported) return [];
    final raw = await _channel.invokeListMethod<dynamic>('listContacts') ?? [];
    return raw.map((entry) {
      final map = Map<dynamic, dynamic>.from(entry as Map);
      return <String, String>{
        'name': map['name']?.toString() ?? '',
        'number': map['number']?.toString() ?? '',
      };
    }).toList(growable: false);
  }

  static Future<String?> pickContact() => _channel.invokeMethod<String>('pickContact');
  /// Opens Android's "default SMS app" dialog; true when PayamYar was chosen.
  static Future<bool> requestDefault() async => await _channel.invokeMethod<bool>('requestDefault') ?? false;
  static Future<void> openAppSettings() => _channel.invokeMethod<bool>('openAppSettings');
  static Future<void> manageBlocked() => _channel.invokeMethod<bool>('manageBlocked');
  static Future<void> block(String address) => _channel.invokeMethod<bool>('blockNumber', {'address': address});

  static Future<SpecialAccess> specialAccess() async {
    if (!supported) return const SpecialAccess();
    final raw = await _channel.invokeMapMethod<String, bool>('specialAccess') ?? {};
    return SpecialAccess(battery: raw['battery'] ?? true, exactAlarm: raw['exactAlarm'] ?? true,
      notifications: raw['notifications'] ?? true);
  }
  static Future<void> requestBatteryExemption() => _channel.invokeMethod<bool>('requestBatteryExemption');
  static Future<void> requestExactAlarm() => _channel.invokeMethod<bool>('requestExactAlarm');
  static Future<void> openNotificationSettings() => _channel.invokeMethod<bool>('openNotificationSettings');
  static Future<void> clearNotifications(String address) async {
    if (supported) await _channel.invokeMethod<void>('clearNotifications', {'address': address});
  }

  static Future<Map<String, String>> contactNames(List<String> addresses) async {
    if (!supported || addresses.isEmpty) return {};
    final raw = await _channel.invokeMapMethod<String, String>('contactNames', {'addresses': addresses});
    return raw ?? {};
  }
  static Future<List<Map<dynamic, dynamic>>> subscriptions() async =>
    (await _channel.invokeListMethod<dynamic>('subscriptions') ?? []).map((e) => Map<dynamic, dynamic>.from(e as Map)).toList();
  static Future<Map<String, dynamic>?> composeIntent() => _channel.invokeMapMethod<String, dynamic>('takeComposeIntent');
  static Future<String> queue(String to, String body, int sim, {Duration delay = const Duration(seconds: 5)}) async =>
    await _channel.invokeMethod<String>('queueSms', {
      'to': normalizeNumber(to), 'body': body, 'subscriptionId': sim, 'delayMs': delay.inMilliseconds,
    }) ?? '';
  /// Native queue survives the conversation screen and can be restored after restart.
  static Future<List<Map<dynamic, dynamic>>> pending() async {
    if (!supported) return [];
    final raw = await _channel.invokeListMethod<dynamic>('pendingSms') ?? [];
    return raw.map((item) => Map<dynamic, dynamic>.from(item as Map)).toList();
  }
  static Future<bool> cancel(String id) async =>
    await _channel.invokeMethod<bool>('cancelSms', {'requestId': id}) ?? false;
  static Future<void> markRead(List<int> ids) async {
    for (var start = 0; start < ids.length; start += 500) {
      await _channel.invokeMethod<void>('markRead', {'ids': ids.sublist(start, (start + 500).clamp(0, ids.length))});
    }
  }
  static Future<void> delete(List<int> ids) async {
    for (var start = 0; start < ids.length; start += 500) {
      await _channel.invokeMethod<void>('deleteMessages', {'ids': ids.sublist(start, (start + 500).clamp(0, ids.length))});
    }
  }
}
