import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../brand_mark.dart';
import 'vault.dart';

/// App PIN lock and screenshot protection.
/// The PIN itself lives only as a salted hash in the Android Keystore vault.
class AppLock extends ChangeNotifier {
  /// One lock for the whole app (hosted by main.dart, configured from Settings).
  static final instance = AppLock();
  static const _channel = MethodChannel('ir.honarmardomi.payamyar/sms');
  static const vaultName = 'app';
  static const relockChoices = [0, 30, 60, 300, 900];

  bool enabled = false;
  bool secureScreen = false;
  /// Seconds in the background before the lock comes back (0 = immediately).
  int relockSeconds = 30;
  bool locked = false;
  bool loaded = false;
  DateTime? _pausedAt;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool('appLock') ?? false;
      secureScreen = p.getBool('secureScreen') ?? false;
      relockSeconds = p.getInt('relockSeconds') ?? 30;
      if (!relockChoices.contains(relockSeconds)) relockSeconds = 30;
      if (enabled && !await Vault.hasPin(vaultName)) enabled = false;
      locked = enabled;
      await _applySecure();
    } catch (_) {
      // Never leave the app covered because the lock state could not be read.
    } finally {
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('appLock', enabled);
    await p.setBool('secureScreen', secureScreen);
    await p.setInt('relockSeconds', relockSeconds);
  }

  Future<void> _applySecure() async {
    if (!Platform.isAndroid) return;
    try {
      // The lock also hides the app preview in "recent apps".
      await _channel.invokeMethod<void>('setSecureScreen', {'on': secureScreen || enabled});
    } catch (_) {}
  }

  Future<void> enable(String pin) async {
    await Vault.setPin(vaultName, pin);
    enabled = true;
    locked = false;
    await _save();
    await _applySecure();
    notifyListeners();
  }

  Future<void> disable() async {
    await Vault.remove(vaultName);
    enabled = false;
    locked = false;
    await _save();
    await _applySecure();
    notifyListeners();
  }

  Future<void> setSecureScreen(bool v) async {
    secureScreen = v;
    await _save();
    await _applySecure();
    notifyListeners();
  }

  Future<void> setRelock(int seconds) async {
    relockSeconds = seconds;
    await _save();
    notifyListeners();
  }

  Future<PinCheck> unlock(String pin) async {
    final r = await Vault.verifyPin(vaultName, pin);
    if (r.ok || r.notSet) {
      locked = false;
      notifyListeners();
    }
    return r;
  }

  void paused() => _pausedAt ??= DateTime.now();

  void resumed() {
    final at = _pausedAt;
    _pausedAt = null;
    if (!enabled || at == null) return;
    if (DateTime.now().difference(at).inSeconds >= relockSeconds) {
      locked = true;
      notifyListeners();
    }
  }
}

/// Covers the whole app with the PIN screen while [AppLock.locked].
class LockGate extends StatefulWidget {
  final AppLock lock;
  final Widget child;
  const LockGate({super.key, required this.lock, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) widget.lock.paused();
    if (state == AppLifecycleState.resumed) widget.lock.resumed();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.lock,
        builder: (context, _) => Stack(children: [
          widget.child,
          // Until the lock state is read, cover the app so private chats never flash on screen.
          if (!widget.lock.loaded)
            Positioned.fill(child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)),
          if (widget.lock.locked)
            Positioned.fill(
              child: PinScreen(
                title: 'پیامیار قفل است',
                subtitle: 'رمز برنامه را وارد کنید',
                onSubmit: (pin) async {
                  final r = await widget.lock.unlock(pin);
                  return r.ok ? null : r.message;
                },
              ),
            ),
        ]),
      );
}

/// Full-screen numeric PIN pad. [onSubmit] returns an error text, or null on success.
class PinScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final int minLength;
  final Future<String?> Function(String pin) onSubmit;
  final VoidCallback? onCancel;
  const PinScreen({super.key, required this.title, required this.subtitle, required this.onSubmit,
      this.minLength = 4, this.onCancel});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String pin = '';
  String? error;
  bool busy = false;

  Future<void> _submit() async {
    if (pin.length < widget.minLength || busy) return;
    setState(() => busy = true);
    final e = await widget.onSubmit(pin);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = e;
      if (e != null) pin = '';
    });
    if (e != null) HapticFeedback.heavyImpact();
  }

  void _press(String d) {
    if (busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      error = null;
      if (d == '<') {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
      } else if (pin.length < 12) {
        pin += d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    Widget key(String d) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: AspectRatio(
              aspectRatio: 1.5,
              child: Material(
                color: Colors.white.withValues(alpha: d == '' ? 0 : .12),
                borderRadius: BorderRadius.circular(22),
                child: d == ''
                    ? const SizedBox()
                    : InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => d == 'ok' ? _submit() : _press(d),
                        child: Center(
                          child: d == '<'
                              ? const Icon(Icons.backspace_outlined, color: Colors.white)
                              : d == 'ok'
                                  ? busy
                                      ? const SizedBox(width: 22, height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.check_rounded, color: Color(0xFFFFD27A), size: 30)
                                  : Text(fa[int.parse(d)],
                                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                        ),
                      ),
              ),
            ),
          ),
        );
    return Material(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
              colors: [Color(0xFF0B6C70), Color(0xFF12444C), Color(0xFF17353B)]),
        ),
        child: SafeArea(
          child: Column(children: [
            if (widget.onCancel != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: widget.onCancel),
              ),
            const Spacer(),
            const PayamYarLogotype(height: 44, color: Colors.white),
            const SizedBox(height: 22),
            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(widget.subtitle, style: const TextStyle(color: Color(0xFFD8E9E6), fontSize: 13)),
            const SizedBox(height: 22),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < (pin.length < widget.minLength ? widget.minLength : pin.length); i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < pin.length ? const Color(0xFFFFD27A) : Colors.transparent,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                  ),
              ]),
            ),
            SizedBox(
              height: 44,
              child: Center(
                child: error == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(error!, textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.errorContainer, fontSize: 12.5)),
                      ),
              ),
            ),
            const Spacer(),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(children: [
                  for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['<', '0', 'ok']])
                    Row(children: [for (final d in row) key(d)]),
                ]),
              ),
            ),
            const SizedBox(height: 18),
          ]),
        ),
      ),
    );
  }
}

/// Asks for a new PIN twice. Returns the PIN, or null when cancelled.
Future<String?> askNewPin(BuildContext context, {String title = 'رمز جدید', int minLength = 4}) async {
  String? first;
  final completer = Completer<String?>();
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => PinScreen(
        key: ValueKey(first == null),
        title: title,
        subtitle: first == null ? 'یک رمز $minLength تا ۱۲ رقمی انتخاب کنید' : 'رمز را دوباره وارد کنید',
        minLength: minLength,
        onCancel: () => Navigator.pop(ctx),
        onSubmit: (pin) async {
          if (first == null) {
            setState(() => first = pin);
            return null;
          }
          if (first != pin) {
            setState(() => first = null);
            return 'دو رمز یکسان نبودند؛ از نو وارد کنید.';
          }
          if (!completer.isCompleted) completer.complete(pin);
          if (ctx.mounted) Navigator.pop(ctx);
          return null;
        },
      ),
    ),
  ));
  if (!completer.isCompleted) completer.complete(null);
  return completer.future;
}

/// Settings page: app lock on/off, change PIN, relock delay, screenshot protection.
class AppLockSettingsPage extends StatelessWidget {
  final AppLock lock;
  final void Function(String)? onNotice;
  const AppLockSettingsPage({super.key, required this.lock, this.onNotice});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String delay(int s) => s == 0 ? 'فوراً' : s < 60 ? '$s ثانیه' : '${s ~/ 60} دقیقه';
    return Scaffold(
      appBar: AppBar(title: const Text('قفل برنامه و امنیت')),
      body: ListenableBuilder(
        listenable: lock,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: Icon(Icons.lock_rounded, color: scheme.primary),
                title: const Text('قفل برنامه با رمز'),
                subtitle: const Text('هنگام باز شدن پیامیار رمز پرسیده می‌شود'),
                value: lock.enabled,
                onChanged: (v) async {
                  if (v) {
                    final pin = await askNewPin(context, title: 'رمز قفل پیامیار');
                    if (pin != null) {
                      await lock.enable(pin);
                      onNotice?.call('قفل برنامه فعال شد.');
                    }
                  } else {
                    await lock.disable();
                    onNotice?.call('قفل برنامه غیرفعال شد.');
                  }
                },
              ),
              if (lock.enabled) ...[
                ListTile(
                  leading: Icon(Icons.password_rounded, color: scheme.primary),
                  title: const Text('تغییر رمز'),
                  onTap: () async {
                    final pin = await askNewPin(context, title: 'رمز جدید قفل');
                    if (pin != null) {
                      await lock.enable(pin);
                      onNotice?.call('رمز تغییر کرد.');
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.timer_outlined, color: scheme.primary),
                  title: const Text('قفل دوباره پس از خروج'),
                  subtitle: Text(delay(lock.relockSeconds)),
                  trailing: DropdownButton<int>(
                    value: lock.relockSeconds,
                    underline: const SizedBox(),
                    items: [for (final s in AppLock.relockChoices) DropdownMenuItem(value: s, child: Text(delay(s)))],
                    onChanged: (v) => v == null ? null : lock.setRelock(v),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: Icon(Icons.screenshot_monitor_rounded, color: scheme.primary),
              title: const Text('جلوگیری از عکس صفحه'),
              subtitle: const Text('عکس و فیلم از صفحه و پیش‌نمایش در برنامه‌های اخیر مسدود می‌شود'),
              value: lock.secureScreen || lock.enabled,
              onChanged: lock.enabled ? null : lock.setSecureScreen,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'رمز روی سرور یا در متن ساده ذخیره نمی‌شود؛ فقط اثر رمزنگاری‌شده آن در انبار امن اندروید (Keystore) نگه داشته می‌شود. '
              'پس از ۵ تلاش نادرست، ورود برای مدتی قفل می‌شود.',
              style: TextStyle(fontSize: 12.5, height: 1.8),
            ),
          ),
        ]),
      ),
    );
  }
}
