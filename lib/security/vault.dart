import 'dart:io';
import 'package:flutter/services.dart';

/// Result of checking a PIN against the secure vault.
class PinCheck {
  final bool ok;
  final bool notSet;
  final int attemptsLeft;
  final int lockedSeconds;
  const PinCheck({this.ok = false, this.notSet = false, this.attemptsLeft = 0, this.lockedSeconds = 0});

  static PinCheck parse(String raw) {
    if (raw == 'ok') return const PinCheck(ok: true);
    if (raw == 'none') return const PinCheck(notSet: true);
    if (raw == 'unavailable') return const PinCheck();
    final parts = raw.split(':');
    final n = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (parts.first == 'locked') return PinCheck(lockedSeconds: n);
    return PinCheck(attemptsLeft: n);
  }

  String get message {
    if (ok) return '';
    if (notSet) return 'کلید ورود یافت نشد. برای حفظ حریم خصوصی برنامه قفل می‌ماند؛ بازیابی امن لازم است.';
    if (attemptsLeft == 0 && lockedSeconds == 0) return 'کلید امنیتی دستگاه در دسترس نیست؛ برنامه برای محافظت از پیام‌ها قفل می‌ماند.';
    if (lockedSeconds > 0) {
      final m = (lockedSeconds / 60).ceil();
      return 'به دلیل تلاش‌های نادرست، $m دقیقه دیگر دوباره امتحان کنید.';
    }
    return 'رمز نادرست است؛ $attemptsLeft تلاش دیگر باقی است.';
  }
}

/// Android Keystore-backed secret storage (see SecureVault.kt).
/// On other platforms (tests, desktop preview) an in-memory store is used.
class Vault {
  static const _c = MethodChannel('ir.honarmardomi.payamyar/vault');
  static bool get _native => Platform.isAndroid;
  static final Map<String, String> _memory = {};

  static Future<String?> get(String name) async =>
      _native ? await _c.invokeMethod<String>('get', {'name': name}) : _memory[name];

  static Future<void> put(String name, String value) async {
    if (_native) {
      await _c.invokeMethod<bool>('put', {'name': name, 'value': value});
    } else {
      _memory[name] = value;
    }
  }

  static Future<void> remove(String name) async {
    if (_native) {
      await _c.invokeMethod<bool>('remove', {'name': name});
    } else {
      _memory.remove(name);
      _memory.remove('pin_$name');
    }
  }

  static Future<void> setPin(String name, String pin) async {
    if (_native) {
      await _c.invokeMethod<bool>('setPin', {'name': name, 'pin': pin});
    } else {
      _memory['pin_$name'] = pin;
    }
  }

  static Future<bool> hasPin(String name) async =>
      _native ? await _c.invokeMethod<bool>('hasPin', {'name': name}) ?? false : _memory.containsKey('pin_$name');

  static Future<PinCheck> verifyPin(String name, String pin) async {
    if (!_native) {
      final stored = _memory['pin_$name'];
      return PinCheck.parse(stored == null ? 'none' : stored == pin ? 'ok' : 'wrong:4');
    }
    try {
      return PinCheck.parse(await _c.invokeMethod<String>('verifyPin', {'name': name, 'pin': pin}) ?? 'unavailable');
    } catch (_) {
      return const PinCheck(); // Fail closed on Android Keystore errors.
    }
  }
}
