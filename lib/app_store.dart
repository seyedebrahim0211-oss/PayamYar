import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'conversation_logic.dart';
import 'finance_logic.dart';
import 'message_logic.dart';
import 'sms_bridge.dart';
import 'update_service.dart';

class PendingSend {
  final String id;
  final String to;
  final String body;
  final DateTime deadline;
  final bool scheduled;
  PendingSend(this.id, this.to, this.body, this.deadline, {this.scheduled = false});
}

/// Per-conversation values computed once while messages are grouped, so list rows are cheap to draw.
class ConvInfo {
  int unread = 0;
  final MessageCategory category;
  final bool suspicious;
  ConvInfo(this.category, this.suspicious);
}

class ReportData {
  final int revision;
  final int deposits;
  final int withdrawals;
  final List<FinanceEntry> recent;
  final List<AccountBalance> balances;
  final Map<MessageCategory, int> counts;
  final List<Conversation> top;
  const ReportData(this.revision, this.deposits, this.withdrawals, this.recent,
      this.balances, this.counts, this.top);
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
  SpecialAccess access = const SpecialAccess();
  bool loading = false;
  bool loadingAll = false;
  int loadedCount = 0;
  String? error;

  /// Newest first.
  List<MessageRecord> messages = [];
  List<Conversation> conversations = [];
  final Map<String, List<MessageRecord>> _groups = {};
  final Map<String, ConvInfo> _info = {};
  final Map<String, String> _keyCache = {};
  /// Bumped whenever messages change; lets screens cache derived data.
  int revision = 0;

  final Map<String, String> names = {};
  final Set<String> archived = {};
  final Set<String> pinned = {};
  /// Conversation key -> id of the message pinned at the top of that conversation.
  final Map<String, int> pinnedMessages = {};
  List<String> templates = [];
  List<Map<dynamic, dynamic>> sims = [];
  int selectedSim = -1;
  final List<PendingSend> pendingSends = [];
  ReleaseInfo? update;
  bool updateDismissed = false;
  bool updateCheckFailed = false;
  /// null when not downloading; 0..1 while the new version downloads.
  double? updateProgress;
  void Function(String message)? onNotice;
  VoidCallback? onComposeIntent;
  Timer? _debounce;
  int _generation = 0;
  List<MessageRecord> _buffer = [];
  bool _progressive = false;
  ReportData? _report;

  bool get isDefault => permissions.isDefault;
  bool get needsOnboarding => android && (!permissions.canRead || !onboarded);

  static List<MessageRecord> _sample() {
    final now = DateTime.now();
    return [
      MessageRecord(sender: 'هنر مردمی', body: 'به پیامیار خوش آمدید. پیام‌های گوشی شما اینجا نمایش داده می‌شوند.', date: now.subtract(const Duration(minutes: 5)), read: false, id: 1),
      MessageRecord(sender: 'بانک', body: 'واریز ۲۵۰,۰۰۰ تومان به حساب شما. موجودی: ۱,۲۰۰,۰۰۰ تومان', date: now.subtract(const Duration(hours: 3)), id: 2),
      MessageRecord(sender: 'سامانه', body: 'کد تأیید شما: 48213', date: now.subtract(const Duration(days: 1)), id: 3),
      MessageRecord(sender: '09121234567', body: 'سلام، فردا ساعت ۱۰ جلسه داریم.', date: now.subtract(const Duration(days: 2)), id: 4),
      MessageRecord(sender: 'فروشگاه', body: 'تخفیف ویژه امروز تا ۵۰٪', date: now.subtract(const Duration(days: 9)), id: 5),
    ];
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    onboarded = p.getBool('onboarded') ?? false;
    archived.addAll(p.getStringList('archived') ?? []);
    pinned.addAll(p.getStringList('pinned') ?? []);
    for (final row in p.getStringList('pinned_messages') ?? const <String>[]) {
      final i = row.lastIndexOf('|');
      final id = i < 0 ? null : int.tryParse(row.substring(i + 1));
      if (id != null) pinnedMessages[row.substring(0, i)] = id;
    }
    templates = p.getStringList('templates_user') ?? [];
    if (android) {
      SmsBridge.listen(_onNativeEvent);
      await checkPermissions();
      if (permissions.canRead) unawaited(loadAll());
      try {
        final queued = await SmsBridge.pending();
        for (final item in queued) {
          final due = DateTime.fromMillisecondsSinceEpoch((item['due'] as num).toInt());
          if (due.isAfter(DateTime.now())) {
            final pending = PendingSend(item['id'] as String, item['to'] as String,
              item['body'] as String, due, scheduled: item['scheduled'] == true);
            pendingSends.add(pending);
            unawaited(_watch(pending));
          }
        }
      } catch (_) { /* A queue read failure must not block the inbox. */ }
      unawaited(checkForUpdate());
    } else {
      messages = _sample();
      _rebuild();
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> _onNativeEvent(String event, Object? args) async {
    switch (event) {
      case 'messagesPage':
        _onPage(args);
      case 'updateProgress':
        updateProgress = ((args as num?)?.toDouble() ?? 0) / 100;
        notifyListeners();
      case 'composeIntent':
        onComposeIntent?.call();
      default:
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), refresh);
    }
  }

  // ───────────── permissions ─────────────

  Future<void> checkPermissions() async {
    if (!android) return;
    try {
      available = await SmsBridge.available();
      permissions = await SmsBridge.status();
      access = await SmsBridge.specialAccess();
    } catch (_) {
      error = 'وضعیت دسترسی‌ها خوانده نشد.';
    }
    notifyListeners();
  }

  Future<SmsPermissionState> requestPermissions() async {
    permissions = await SmsBridge.request();
    if (permissions.canRead && messages.isEmpty) unawaited(loadAll());
    notifyListeners();
    return permissions;
  }

  Future<bool> requestDefault() async {
    final ok = await SmsBridge.requestDefault();
    await checkPermissions();
    if (ok) unawaited(refresh());
    return ok;
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarded', true);
    notifyListeners();
  }

  // ───────────── updates ─────────────

  /// Reads the release info published on honarmardomi.ir; quiet unless a newer version exists.
  Future<bool> checkForUpdate({bool manual = false}) async {
    updateCheckFailed = false;
    try {
      final info = await UpdateService.check();
      final previousVersion = update?.version;
      update = info.available && UpdateService.trusted(info.url) ? info : null;
      if (manual || (update != null && update!.version != previousVersion)) {
        updateDismissed = false;
      }
      if (!manual && update != null && update!.version != previousVersion) {
        onNotice?.call('نسخه جدید پیامیار ${update!.version} آماده است؛ از همین برنامه به‌روزرسانی کنید.');
      }
      notifyListeners();
      return update != null;
    } catch (_) {
      updateCheckFailed = true;
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
      final state = await SmsBridge.installUpdate(info.url, sha256: info.sha256);
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

  // ───────────── loading ─────────────

  /// Reads every SMS in one native pass. The first 150 messages appear at once; the rest follow in large pages.
  Future<void> loadAll() async {
    if (!android || loadingAll) return;
    loadingAll = true;
    error = null;
    loadedCount = 0;
    final generation = ++_generation;
    _buffer = [];
    // First load fills the screen page by page; a reload swaps in the result at the end.
    _progressive = messages.isEmpty;
    if (_progressive) _reset();
    notifyListeners();
    try {
      await SmsBridge.loadAll(generation);
      if (generation != _generation) return;
      messages = _buffer;
      if (!_progressive) _rebuild();
      _buffer = [];
      sims = await SmsBridge.subscriptions();
      if (!sims.any((s) => s['id'] == selectedSim)) selectedSim = -1;
      unawaited(_loadNames());
    } catch (_) {
      error = 'خواندن پیامک‌های گوشی ممکن نشد.';
    } finally {
      if (generation == _generation) {
        loadingAll = false;
        notifyListeners();
      }
    }
  }

  void _onPage(Object? args) {
    if (args is! Map || args['generation'] != _generation || !loadingAll) return;
    final page = SmsBridge.fromColumns(args);
    _buffer.addAll(page);
    loadedCount = _buffer.length;
    if (_progressive) {
      messages = _buffer;
      _ingest(page);
      revision++;
    }
    notifyListeners();
  }

  /// Re-reads only the newest messages and merges them, so a change never reloads the whole inbox.
  Future<void> refresh() async {
    if (!android) return;
    if (loadingAll || loading) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), refresh);
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
      const window = 300;
      final page = await SmsBridge.read(limit: window);
      if (page.length < window) {
        messages = page;
      } else {
        final last = page.last;
        final older = messages.where((m) => m.date.isBefore(last.date) ||
            (m.date == last.date && (m.id ?? 0) < (last.id ?? 0)));
        messages = [...page, ...older];
      }
      _rebuild();
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

  // ───────────── grouping ─────────────

  void _reset() {
    _groups.clear();
    _info.clear();
    conversations = [];
  }

  /// Adds messages (already newest-first) to their conversations. Conversations stay ordered by latest message.
  void _ingest(List<MessageRecord> page) {
    for (final m in page) {
      if (m.sender.isEmpty) continue;
      final k = key(m.sender);
      var list = _groups[k];
      if (list == null) {
        list = _groups[k] = [];
        conversations.add(Conversation(m.sender, list));
        _info[k] = ConvInfo(MessageLogic.category(m), !m.outgoing && MessageLogic.suspicious(m.body));
      }
      list.add(m);
      if (!m.read && !m.outgoing) _info[k]!.unread++;
    }
  }

  void _rebuild() {
    _reset();
    _ingest(messages);
    revision++;
  }

  String displayName(String address) {
    final name = names[address];
    return name == null || name.isEmpty ? address : name;
  }

  String key(String address) => _keyCache[address] ??= ConversationLogic.normalize(address);
  bool isArchived(String address) => archived.contains(key(address));
  bool isPinned(String address) => pinned.contains(key(address));

  Conversation? conversationFor(String address) {
    final list = _groups[key(address)];
    if (list == null || list.isEmpty) return null;
    return Conversation(list.first.sender, list);
  }

  ConvInfo? infoFor(String address) => _info[key(address)];
  int unreadCount(Conversation c) => _info[key(c.address)]?.unread ?? 0;
  MessageCategory categoryOf(Conversation c) => _info[key(c.address)]?.category ?? MessageCategory.personal;
  int get unreadConversations => _info.values.where((i) => i.unread > 0).length;

  /// Pinned conversations first, then by latest message.
  List<Conversation> visible({required bool archive}) {
    final top = <Conversation>[], rest = <Conversation>[];
    for (final c in conversations) {
      final k = key(c.address);
      if (archived.contains(k) != archive) continue;
      (pinned.contains(k) ? top : rest).add(c);
    }
    return [...top, ...rest];
  }

  ReportData get report {
    final cached = _report;
    if (cached != null && cached.revision == revision) return cached;
    final since = DateTime.now().subtract(const Duration(days: 30));
    final recent = <FinanceEntry>[];
    final counts = <MessageCategory, int>{for (final c in MessageCategory.values) c: 0};
    for (final m in messages) {
      final category = MessageLogic.category(m);
      counts[category] = counts[category]! + 1;
      if (category == MessageCategory.banking && m.date.isAfter(since)) {
        final entry = FinanceLogic.parse(m);
        if (entry != null) recent.add(entry);
      }
    }
    final top = conversations.toList()..sort((a, b) => b.count.compareTo(a.count));
    return _report = ReportData(revision, FinanceLogic.total(recent, FinanceKind.deposit),
      FinanceLogic.total(recent, FinanceKind.withdrawal), recent,
      FinanceLogic.latestBalances(messages), counts, top.take(5).toList());
  }

  // ───────────── local organisation ─────────────

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('archived', archived.toList());
    await p.setStringList('pinned', pinned.toList());
    await p.setStringList('templates_user', templates);
    await p.setStringList('pinned_messages', [for (final e in pinnedMessages.entries) '${e.key}|${e.value}']);
  }

  void toggleArchive(String address) {
    final k = key(address);
    if (!archived.remove(k)) archived.add(k);
    notifyListeners();
    _savePrefs();
  }

  void togglePin(String address) {
    final k = key(address);
    final nowPinned = !pinned.remove(k);
    if (nowPinned) pinned.add(k);
    notifyListeners();
    _savePrefs();
    onNotice?.call(nowPinned ? 'گفتگو بالای فهرست سنجاق شد.' : 'سنجاق برداشته شد.');
  }

  int? pinnedMessageId(String address) => pinnedMessages[key(address)];

  void togglePinMessage(String address, int id) {
    final k = key(address);
    if (pinnedMessages[k] == id) {
      pinnedMessages.remove(k);
    } else {
      pinnedMessages[k] = id;
    }
    notifyListeners();
    _savePrefs();
  }

  void addTemplate(String text) {
    final t = text.trim();
    if (t.isEmpty || templates.contains(t)) return;
    templates = [t, ...templates];
    notifyListeners();
    _savePrefs();
  }

  void removeTemplate(String text) {
    templates = templates.where((t) => t != text).toList();
    notifyListeners();
    _savePrefs();
  }

  // ───────────── message actions ─────────────

  /// Marks a conversation read at once on screen, then writes it to the phone in the background.
  Future<void> markRead(Conversation c) async {
    final k = key(c.address);
    if (android) unawaited(SmsBridge.clearNotifications(c.address));
    final ids = <int>{for (final m in c.messages) if (!m.read && !m.outgoing && m.id != null) m.id!};
    if (ids.isEmpty) return;
    if (android && !isDefault) return;
    void patch(List<MessageRecord> list) {
      for (var i = 0; i < list.length; i++) {
        if (ids.contains(list[i].id)) list[i] = _copy(list[i], read: true);
      }
    }
    patch(_groups[k] ?? const []);
    if (!identical(_groups[k], messages)) patch(messages);
    _info[k]?.unread = 0;
    revision++;
    notifyListeners();
    if (!android) return;
    try {
      await SmsBridge.markRead(ids.toList());
    } catch (_) {
      onNotice?.call('خوانده‌شدن پیام‌ها ثبت نشد.');
    }
  }

  Future<void> markAllRead() async {
    if (android && !isDefault) {
      onNotice?.call('برای این کار، پیامیار باید پیام‌رسان پیش‌فرض باشد.');
      return;
    }
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
    pinnedMessages.removeWhere((_, id) => set.contains(id));
    _rebuild();
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
  Future<PendingSend?> send(String to, String body, {DateTime? scheduledAt}) async {
    final text = body.trim();
    final target = to.trim();
    if (text.isEmpty || target.isEmpty) return null;
    if (!android) {
      messages = [MessageRecord(sender: target, body: text, date: DateTime.now(), outgoing: true, type: 2, id: DateTime.now().millisecondsSinceEpoch), ...messages];
      _rebuild();
      notifyListeners();
      return null;
    }
    try {
      final now = DateTime.now();
      final delay = scheduledAt == null
          ? const Duration(seconds: 5)
          : scheduledAt.difference(now);
      if (delay.inMilliseconds < 5000 || delay > const Duration(days: 30)) {
        onNotice?.call('زمان ارسال را بین ۵ ثانیه تا ۳۰ روز آینده تنظیم کنید.');
        return null;
      }
      final id = await SmsBridge.queue(target, text, selectedSim, delay: delay);
      final pending = PendingSend(id, target, text, now.add(delay), scheduled: scheduledAt != null);
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
    for (var i = 0; i < 120 && (state == 'queued' || state == 'pending'); i++) {
      try {
        state = await SmsBridge.sendStatus(p.id);
      } catch (_) {
        break;
      }
      if (state == 'cancelled') break;
      if (state == 'queued' || state == 'pending') {
        await Future<void>.delayed(
          p.scheduled ? const Duration(seconds: 3) : const Duration(milliseconds: 600));
      }
    }
    pendingSends.remove(p);
    if (state.startsWith('send_failed')) {
      final reason = state.contains(':') ? state.substring(state.indexOf(':') + 1) : '';
      onNotice?.call(reason.isEmpty
          ? 'ارسال پیامک ناموفق بود. سیم‌کارت، اعتبار و آنتن را بررسی کنید.'
          : 'ارسال پیامک انجام نشد: $reason');
    } else if (state == 'delivery_failed') {
      onNotice?.call('گزارش تحویل پیامک ناموفق است؛ ممکن است پیام در شبکه پذیرفته شده باشد.');
    } else if (state == 'send_unconfirmed') {
      // Vendor ROMs can return RESULT_CANCELED even when the SMS leaves the device.
      // This is not an error: do not show a failure snackbar or encourage a duplicate send.
      // The conversation retains a neutral status until a real network receipt arrives.
    }
    notifyListeners();
    // Coalesce per-recipient confirmations; a 500-recipient batch must not
    // re-query the entire SMS inbox hundreds of times.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => unawaited(refresh()));
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
