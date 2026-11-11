import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'conversation_logic.dart';
import 'message_logic.dart';
import 'sms_bridge.dart';
import 'update_service.dart';

class PendingSend {
  final String id;
  final String to;
  final String body;
  final DateTime deadline;
  PendingSend(this.id, this.to, this.body, this.deadline);
}

/// Single source of truth for messages, permissions and local preferences.
class AppStore extends ChangeNotifier {
  AppStore({this.android = false});

  /// True on a real Android phone; elsewhere (tests, Windows) the app shows sample messages.
  final bool android;

  bool initialized = false;
  bool onboarded = false;
  bool available = false;
  SmsPermissionState permissions = const SmsPermissionState(canRead: false, canSend: false);
  bool loading = false;
  bool loadingAll = false;
  String? error;
  List<MessageRecord> messages = [];
  List<Conversation> conversations = [];
  final Map<String, String> names = {};
  final Set<String> archived = {};
  final Set<String> pinned = {};
  List<String> templates = [];
  List<Map<dynamic, dynamic>> sims = [];
  int selectedSim = -1;
  final List<PendingSend> pendingSends = [];
  ReleaseInfo? update;
  bool updateDismissed = false;
  /// null when not downloading; 0..1 while the new version downloads.
  double? updateProgress;
  void Function(String message)? onNotice;

  bool get isDefault => permissions.isDefault;
  bool get needsOnboarding => android && (!permissions.canRead || !onboarded);

  static final _sample = <MessageRecord>[
    MessageRecord(sender: 'هنر مردمی', body: 'به پیامیار خوش آمدید. پیام‌های گوشی شما اینجا نمایش داده می‌شوند.', date: DateTime.now().subtract(const Duration(minutes: 5)), read: false, id: 1),
    MessageRecord(sender: 'بانک', body: 'واریز ۲۵۰,۰۰۰ تومان به حساب شما. موجودی: ۱,۲۰۰,۰۰۰ تومان', date: DateTime.now().subtract(const Duration(hours: 3)), id: 2),
    MessageRecord(sender: 'سامانه', body: 'کد تأیید شما: 48213', date: DateTime.now().subtract(const Duration(days: 1)), id: 3),
    MessageRecord(sender: '09121234567', body: 'سلام، فردا ساعت ۱۰ جلسه داریم.', date: DateTime.now().subtract(const Duration(days: 2)), id: 4),
    MessageRecord(sender: 'فروشگاه', body: 'تخفیف ویژه امروز تا ۵۰٪', date: DateTime.now().subtract(const Duration(days: 9)), id: 5),
  ];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    onboarded = p.getBool('onboarded') ?? false;
    archived.addAll(p.getStringList('archived') ?? []);
    pinned.addAll(p.getStringList('pinned') ?? []);
    templates = p.getStringList('templates') ??
        ['در جلسه هستم، بعداً تماس می‌گیرم.', 'رسیدم.', 'ممنون 🌹', 'چند دقیقه دیگر می‌رسم.'];
    if (android) {
      SmsBridge.listen((event, args) async {
        if (event == 'updateProgress') {
          updateProgress = ((args as num?)?.toDouble() ?? 0) / 100;
          notifyListeners();
          return;
        }
        if (event == 'composeIntent') {
          onComposeIntent?.call();
          return;
        }
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), refresh);
      });
      await checkPermissions();
      if (permissions.canRead) unawaited(loadAll());
      unawaited(checkForUpdate());
    } else {
      messages = List.of(_sample);
      _regroup();
    }
    initialized = true;
    notifyListeners();
  }

  VoidCallback? onComposeIntent;
  Timer? _debounce;

  Future<void> checkPermissions() async {
    if (!android) return;
    try {
      available = await SmsBridge.available();
      permissions = await SmsBridge.status();
    } catch (_) {
      error = 'وضعیت دسترسی‌ها خوانده نشد.';
    }
    notifyListeners();
  }

  Future<SmsPermissionState> requestPermissions() async {
    permissions = await SmsBridge.request();
    if (permissions.canRead) unawaited(loadAll());
    notifyListeners();
    return permissions;
  }

  Future<bool> requestDefault() async {
    final ok = await SmsBridge.requestDefault();
    await checkPermissions();
    if (ok) unawaited(refresh());
    return ok;
  }

  /// Reads the release info published on honarmardomi.ir; quiet unless a newer version exists.
  Future<bool> checkForUpdate({bool manual = false}) async {
    try {
      final info = await UpdateService.check();
      update = info.available && UpdateService.trusted(info.url) ? info : null;
      if (manual) updateDismissed = false;
      notifyListeners();
      return update != null;
    } catch (_) {
      if (manual) onNotice?.call('بررسی به‌روزرسانی ممکن نشد؛ اینترنت را بررسی کنید.');
      return false;
    }
  }

  /// Downloads the new version inside the app and opens Android's install screen.
  Future<void> installUpdate() async {
    final info = update;
    if (info == null || updateProgress != null) return;
    if (!android) {
      await UpdateService.openDownload(info.url);
      return;
    }
    updateProgress = 0;
    notifyListeners();
    try {
      final state = await SmsBridge.installUpdate(info.url);
      if (state == 'needs_permission') {
        onNotice?.call('اجازه «نصب برنامه از پیامیار» را روشن کنید و دوباره «به‌روزرسانی» را بزنید.');
      }
    } on PlatformException catch (e) {
      onNotice?.call(e.message ?? 'به‌روزرسانی انجام نشد.');
    } finally {
      updateProgress = null;
      notifyListeners();
    }
  }

  void dismissUpdate() {
    updateDismissed = true;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarded', true);
    notifyListeners();
  }

  /// Reads every SMS on the phone, page by page, showing each page as soon as it arrives.
  Future<void> loadAll() async {
    if (!android || loadingAll) return;
    loadingAll = true;
    error = null;
    notifyListeners();
    try {
      var page = await SmsBridge.read();
      final all = <MessageRecord>[...page];
      messages = List.of(all);
      _regroup();
      notifyListeners();
      while (page.length == SmsBridge.pageSize) {
        page = await SmsBridge.read(before: all.last);
        all.addAll(page);
        messages = List.of(all);
        _regroup();
        notifyListeners();
      }
      sims = await SmsBridge.subscriptions();
      if (!sims.any((s) => s['id'] == selectedSim)) selectedSim = -1;
      unawaited(_loadNames());
    } catch (_) {
      error = 'خواندن پیامک‌های گوشی ممکن نشد.';
    } finally {
      loadingAll = false;
      notifyListeners();
    }
  }

  /// Re-reads the newest page and merges it, so a change does not reload the whole inbox.
  Future<void> refresh() async {
    if (!android) return;
    if (loadingAll || loading) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 1), refresh);
      return;
    }
    loading = true;
    try {
      permissions = await SmsBridge.status();
      if (!permissions.canRead) return;
      if (messages.isEmpty) {
        loading = false;
        await loadAll();
        return;
      }
      final page = await SmsBridge.read();
      if (page.length < SmsBridge.pageSize) {
        messages = page;
      } else {
        final last = page.last;
        final older = messages.where((m) => m.date.isBefore(last.date) ||
            (m.date == last.date && (m.id ?? 0) < (last.id ?? 0)));
        messages = [...page, ...older];
      }
      _regroup();
      unawaited(_loadNames());
    } catch (_) {
      error = 'به‌روزرسانی پیام‌ها انجام نشد.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadNames() async {
    if (!permissions.contacts) return;
    final missing = conversations.map((c) => c.address)
        .where((a) => !names.containsKey(a) && RegExp(r'\d{5}').hasMatch(a)).toList();
    if (missing.isEmpty) return;
    try {
      final found = await SmsBridge.contactNames(missing);
      for (final a in missing) {
        names[a] = found[a] ?? '';
      }
      notifyListeners();
    } catch (_) {
      // Names are optional; numbers are shown instead.
    }
  }

  void _regroup() {
    conversations = ConversationLogic.group(messages.where((m) => m.sender.isNotEmpty));
  }

  String displayName(String address) {
    final name = names[address];
    return name == null || name.isEmpty ? address : name;
  }

  String key(String address) => ConversationLogic.normalize(address);
  bool isArchived(String address) => archived.contains(key(address));
  bool isPinned(String address) => pinned.contains(key(address));

  Conversation? conversationFor(String address) {
    final k = key(address);
    for (final c in conversations) {
      if (key(c.address) == k) return c;
    }
    return null;
  }

  int unreadCount(Conversation c) => c.messages.where((m) => !m.read && !m.outgoing).length;

  List<Conversation> visible({required bool archive}) {
    final list = conversations.where((c) => isArchived(c.address) == archive).toList();
    list.sort((a, b) {
      final pa = isPinned(a.address) ? 1 : 0, pb = isPinned(b.address) ? 1 : 0;
      if (pa != pb) return pb - pa;
      return b.latest.date.compareTo(a.latest.date);
    });
    return list;
  }

  Future<void> _saveSets() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('archived', archived.toList());
    await p.setStringList('pinned', pinned.toList());
    await p.setStringList('templates', templates);
  }

  void toggleArchive(String address) {
    final k = key(address);
    if (!archived.remove(k)) archived.add(k);
    notifyListeners();
    _saveSets();
  }

  void togglePin(String address) {
    final k = key(address);
    if (!pinned.remove(k)) pinned.add(k);
    notifyListeners();
    _saveSets();
  }

  void addTemplate(String text) {
    final t = text.trim();
    if (t.isEmpty || templates.contains(t)) return;
    templates = [...templates, t];
    notifyListeners();
    _saveSets();
  }

  void removeTemplate(String text) {
    templates = templates.where((t) => t != text).toList();
    notifyListeners();
    _saveSets();
  }

  Future<void> markRead(Conversation c) async {
    final ids = c.messages.where((m) => !m.read && !m.outgoing && m.id != null).map((m) => m.id!).toList();
    if (ids.isEmpty) return;
    if (!android) {
      messages = messages.map((m) => ids.contains(m.id) ? _copy(m, read: true) : m).toList();
      _regroup();
      notifyListeners();
      return;
    }
    if (!isDefault) return;
    try {
      await SmsBridge.markRead(ids);
      await refresh();
    } catch (_) {
      onNotice?.call('خوانده‌شدن پیام‌ها ثبت نشد.');
    }
  }

  Future<void> markAllRead() async {
    for (final c in conversations.where((c) => unreadCount(c) > 0).toList()) {
      await markRead(c);
    }
  }

  Future<bool> deleteMessages(List<int> ids) async {
    if (ids.isEmpty) return true;
    if (android) {
      if (!isDefault) {
        onNotice?.call('برای حذف پیام، پیامیار باید پیام‌رسان پیش‌فرض باشد.');
        return false;
      }
      try {
        await SmsBridge.delete(ids);
      } catch (_) {
        onNotice?.call('حذف پیام انجام نشد.');
        return false;
      }
    }
    final set = ids.toSet();
    messages = messages.where((m) => !set.contains(m.id)).toList();
    _regroup();
    notifyListeners();
    return true;
  }

  Future<bool> block(String address) async {
    if (!android) return false;
    try {
      await SmsBridge.block(address);
      onNotice?.call('${displayName(address)} مسدود شد.');
      return true;
    } on PlatformException catch (e) {
      onNotice?.call(e.message ?? 'مسدود کردن انجام نشد.');
      return false;
    }
  }

  /// Queues an SMS with a 5-second undo window. Returns null if sending failed to start.
  Future<PendingSend?> send(String to, String body) async {
    final text = body.trim();
    final target = to.trim();
    if (text.isEmpty || target.isEmpty) return null;
    if (!android) {
      messages = [MessageRecord(sender: target, body: text, date: DateTime.now(), outgoing: true, type: 2, id: DateTime.now().millisecondsSinceEpoch), ...messages];
      _regroup();
      notifyListeners();
      return null;
    }
    try {
      final id = await SmsBridge.queue(target, text, selectedSim);
      final pending = PendingSend(id, target, text, DateTime.now().add(const Duration(seconds: 5)));
      pendingSends.add(pending);
      notifyListeners();
      unawaited(_watch(pending));
      return pending;
    } on PlatformException catch (e) {
      onNotice?.call(e.message ?? 'ارسال ممکن نشد.');
      return null;
    }
  }

  Future<bool> undo(PendingSend p) async {
    final ok = await SmsBridge.cancel(p.id);
    if (ok) {
      pendingSends.remove(p);
      notifyListeners();
      onNotice?.call('ارسال لغو شد.');
    } else {
      onNotice?.call('مهلت لغو تمام شده است.');
    }
    return ok;
  }

  Future<void> _watch(PendingSend p) async {
    final wait = p.deadline.difference(DateTime.now());
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    var state = 'queued';
    for (var i = 0; i < 25 && (state == 'queued' || state == 'pending'); i++) {
      try {
        state = await SmsBridge.sendStatus(p.id);
      } catch (_) {
        break;
      }
      if (state == 'cancelled') break;
      if (state == 'queued' || state == 'pending') await Future<void>.delayed(const Duration(seconds: 1));
    }
    pendingSends.remove(p);
    if (state.startsWith('send_failed')) {
      onNotice?.call('ارسال پیام ناموفق بود. سیم‌کارت و آنتن را بررسی کنید.');
    }
    notifyListeners();
    await refresh();
  }

  static MessageRecord _copy(MessageRecord m, {bool? read}) => MessageRecord(
    sender: m.sender, body: m.body, date: m.date, outgoing: m.outgoing, id: m.id,
    read: read ?? m.read, type: m.type, delivery: m.delivery);

  @override
  void dispose() {
    _debounce?.cancel();
    if (android) SmsBridge.stopListening();
    super.dispose();
  }
}
