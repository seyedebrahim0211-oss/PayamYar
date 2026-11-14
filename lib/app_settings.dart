import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const brand = Color(0xFF087F81);
const palettes = [brand, Color(0xFF305F91), Color(0xFF75539A), Color(0xFF9F5369), Color(0xFF47765F), Color(0xFFA17A37)];

/// How the user is told that an SMS left the phone.
/// Read natively as `flutter.sentFeedback` (FlutterSharedPreferences, stored as Long).
enum SentFeedback { sound, notification, silent }

/// Ready-made chat looks. Order is persisted; append new ones at the end.
enum ChatStyle { traditional, glass, minimal, classic }

const chatStyleNames = {
  ChatStyle.traditional: 'سنتی',
  ChatStyle.glass: 'شیشه‌ای',
  ChatStyle.minimal: 'مینیمال',
  ChatStyle.classic: 'کلاسیک',
};

/// Look of the glass banner shown inside the app when a message arrives.
enum BannerStyle { glass, vivid, minimal }

const bannerStyleNames = {
  BannerStyle.glass: 'شیشه‌ای',
  BannerStyle.vivid: 'رنگی',
  BannerStyle.minimal: 'ساده',
};

/// Ready-made answers offered on the notification and the in-app banner.
const defaultQuickReplies = ['باشه 👍', 'ممنون', 'الان نمی‌تونم صحبت کنم', 'بعداً تماس می‌گیرم', 'رسیدم'];

/// Appearance, sending and privacy preferences.
class AppSettings extends ChangeNotifier {
  int palette = 0;
  ThemeMode mode = ThemeMode.system;
  double scale = 1;
  int fontChoice = 0; // 0 = Vazirmatn, 1 = Android default, 2 = Android serif / Naskh fallback
  bool hidePreview = true;
  bool notifyPreview = false;
  bool notifyIncoming = true;
  bool notifySent = true;

  // ── sending ──
  bool sendDelayEnabled = true;
  /// Undo window before the SMS really leaves, 1..10 seconds.
  int sendDelaySeconds = 5;
  SentFeedback sentFeedback = SentFeedback.sound;
  bool enterToSend = false;
  bool signatureEnabled = false;
  String signature = '';
  bool smartReplies = true;
  /// App-side recipient selection capacity, not an operator sending allowance.
  /// For >500, the user must explicitly opt in; all SMS remain subject to carrier policy.
  int recipientCapacity = 500;
  bool swipeTabs = true;
  bool reduceEffects = false;

  // ── chat look ──
  ChatStyle chatStyle = ChatStyle.traditional;
  double bubbleText = 15.5;

  // ── notification look (the notify* keys are also read natively by Notifier.kt) ──
  bool notifyInApp = true;
  BannerStyle bannerStyle = BannerStyle.glass;
  int bannerTint = 0;
  double bannerBlur = 18;
  double bannerOpacity = .5;
  bool bannerTop = true;
  int bannerSeconds = 6;
  bool bannerCompact = true;
  double bannerMaxWidth = 360;
  bool bannerBubbles = true;
  bool notifyGlassAvatar = true;
  int notifyAvatarShape = 0; // 0 = circle, 1 = soft square
  bool notifyBubbles = false;
  bool notifyQuickReply = true;
  bool notifyOtpCopy = true;
  List<String> quickReplies = List.of(defaultQuickReplies);

  Color get bannerColor => palettes[bannerTint];

  // ── quiet hours (minutes after midnight), read natively ──
  bool quietHours = false;
  int quietStart = 23 * 60;
  int quietEnd = 7 * 60;

  Duration get sendDelay => sendDelayEnabled ? Duration(seconds: sendDelaySeconds) : Duration.zero;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    palette = (p.getInt('palette') ?? 0).clamp(0, palettes.length - 1).toInt();
    mode = ThemeMode.values[(p.getInt('theme') ?? 0).clamp(0, 2).toInt()];
    scale = (p.getDouble('scale') ?? 1).clamp(.9, 1.5).toDouble();
    fontChoice = (p.getInt('fontChoice') ?? 0).clamp(0, 2).toInt();
    hidePreview = p.getBool('privatePreview') ?? true;
    notifyPreview = p.getBool('notifyPreview') ?? false;
    notifyIncoming = p.getBool('notifyIncoming') ?? true;
    notifySent = p.getBool('notifySent') ?? true;
    sendDelayEnabled = p.getBool('sendDelayEnabled') ?? true;
    sendDelaySeconds = (p.getInt('sendDelaySeconds') ?? 5).clamp(1, 10).toInt();
    sentFeedback = SentFeedback.values[(p.getInt('sentFeedback') ?? 0).clamp(0, SentFeedback.values.length - 1).toInt()];
    enterToSend = p.getBool('enterToSend') ?? false;
    signatureEnabled = p.getBool('signatureEnabled') ?? false;
    signature = p.getString('signature') ?? '';
    smartReplies = p.getBool('smartReplies') ?? true;
    recipientCapacity = _capacity(p.getInt('recipientCapacity') ?? 500);
    swipeTabs = p.getBool('swipeTabs') ?? true;
    reduceEffects = p.getBool('reduceEffects') ?? false;
    chatStyle = ChatStyle.values[(p.getInt('chatStyle') ?? 0).clamp(0, ChatStyle.values.length - 1).toInt()];
    bubbleText = (p.getDouble('bubbleText') ?? 15.5).clamp(13, 20).toDouble();
    quietHours = p.getBool('quietHours') ?? false;
    quietStart = (p.getInt('quietStart') ?? 23 * 60).clamp(0, 1439).toInt();
    quietEnd = (p.getInt('quietEnd') ?? 7 * 60).clamp(0, 1439).toInt();
    notifyInApp = p.getBool('notifyInApp') ?? true;
    bannerStyle = BannerStyle.values[(p.getInt('bannerStyle') ?? 0).clamp(0, BannerStyle.values.length - 1).toInt()];
    bannerTint = (p.getInt('bannerTint') ?? palette).clamp(0, palettes.length - 1).toInt();
    bannerBlur = (p.getDouble('bannerBlur') ?? 18).clamp(0, 30).toDouble();
    bannerOpacity = (p.getDouble('bannerOpacity') ?? .5).clamp(.15, .95).toDouble();
    bannerTop = p.getBool('bannerTop') ?? true;
    bannerSeconds = (p.getInt('bannerSeconds') ?? 6).clamp(2, 15).toInt();
    bannerCompact = p.getBool('bannerCompact') ?? true;
    bannerMaxWidth = (p.getDouble('bannerMaxWidth') ?? 360).clamp(280, 520).toDouble();
    bannerBubbles = p.getBool('bannerBubbles') ?? true;
    notifyGlassAvatar = p.getBool('notifyGlassAvatar') ?? true;
    notifyAvatarShape = (p.getInt('notifyAvatarShape') ?? 0).clamp(0, 1).toInt();
    // Floating Android bubbles are retired; ignore the old persisted switch.
    notifyBubbles = false;
    notifyQuickReply = p.getBool('notifyQuickReply') ?? true;
    notifyOtpCopy = p.getBool('notifyOtpCopy') ?? true;
    final replies = p.getString('notifyQuickReplies');
    quickReplies = replies == null ? List.of(defaultQuickReplies) : cleanReplies(replies.split('\n'));
    notifyListeners();
  }

  static int _capacity(int value) => const [500, 1000, 2000].contains(value) ? value : 500;

  Future<void> update({int? palette, ThemeMode? mode, double? scale, int? fontChoice,
      bool? hidePreview, bool? notifyPreview, bool? notifyIncoming, bool? notifySent,
      bool? sendDelayEnabled, int? sendDelaySeconds, SentFeedback? sentFeedback, bool? enterToSend,
      bool? signatureEnabled, String? signature, bool? smartReplies, int? recipientCapacity,
       bool? swipeTabs, bool? reduceEffects, ChatStyle? chatStyle,
      double? bubbleText, bool? quietHours, int? quietStart, int? quietEnd}) async {
    this.palette = palette ?? this.palette;
    this.mode = mode ?? this.mode;
    this.scale = scale ?? this.scale;
    this.fontChoice = fontChoice ?? this.fontChoice;
    this.hidePreview = hidePreview ?? this.hidePreview;
    this.notifyPreview = notifyPreview ?? this.notifyPreview;
    this.notifyIncoming = notifyIncoming ?? this.notifyIncoming;
    this.notifySent = notifySent ?? this.notifySent;
    this.sendDelayEnabled = sendDelayEnabled ?? this.sendDelayEnabled;
    this.sendDelaySeconds = (sendDelaySeconds ?? this.sendDelaySeconds).clamp(1, 10).toInt();
    this.sentFeedback = sentFeedback ?? this.sentFeedback;
    this.enterToSend = enterToSend ?? this.enterToSend;
    this.signatureEnabled = signatureEnabled ?? this.signatureEnabled;
    this.signature = (signature ?? this.signature).trim();
    this.smartReplies = smartReplies ?? this.smartReplies;
    this.recipientCapacity = _capacity(recipientCapacity ?? this.recipientCapacity);
    this.swipeTabs = swipeTabs ?? this.swipeTabs;
    this.reduceEffects = reduceEffects ?? this.reduceEffects;
    this.chatStyle = chatStyle ?? this.chatStyle;
    this.bubbleText = bubbleText ?? this.bubbleText;
    this.quietHours = quietHours ?? this.quietHours;
    this.quietStart = quietStart ?? this.quietStart;
    this.quietEnd = quietEnd ?? this.quietEnd;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('palette', palette);
    await p.setInt('theme', mode.index);
    await p.setDouble('scale', scale);
    await p.setInt('fontChoice', fontChoice);
    await p.setBool('privatePreview', hidePreview);
    // The keys below are also read by native notification code (FlutterSharedPreferences, "flutter." prefix).
    await p.setBool('notifyPreview', notifyPreview);
    await p.setBool('notifyIncoming', notifyIncoming);
    await p.setBool('notifySent', notifySent && sentFeedback != SentFeedback.silent);
    await p.setInt('sentFeedback', sentFeedback.index);
    await p.setBool('quietHours', quietHours);
    await p.setInt('quietStart', quietStart);
    await p.setInt('quietEnd', quietEnd);
    await p.setBool('sendDelayEnabled', sendDelayEnabled);
    await p.setInt('sendDelaySeconds', sendDelaySeconds);
    await p.setBool('enterToSend', enterToSend);
    await p.setBool('signatureEnabled', signatureEnabled);
    await p.setString('signature', signature);
    await p.setBool('smartReplies', smartReplies);
    await p.setInt('recipientCapacity', recipientCapacity);
    await p.setBool('swipeTabs', swipeTabs);
    await p.setBool('reduceEffects', reduceEffects);
    await p.setInt('chatStyle', chatStyle.index);
    await p.setDouble('bubbleText', bubbleText);
    await _saveNotify(p);
  }

  /// Notification look; separate from [update] to keep that signature readable.
  Future<void> updateNotify({bool? notifyInApp, BannerStyle? bannerStyle, int? bannerTint, double? bannerBlur,
      double? bannerOpacity, bool? bannerTop, int? bannerSeconds, bool? bannerCompact,
      double? bannerMaxWidth, bool? bannerBubbles, bool? notifyGlassAvatar,
      int? notifyAvatarShape, bool? notifyBubbles, bool? notifyQuickReply, bool? notifyOtpCopy,
      List<String>? quickReplies}) async {
    this.notifyInApp = notifyInApp ?? this.notifyInApp;
    this.bannerStyle = bannerStyle ?? this.bannerStyle;
    this.bannerTint = (bannerTint ?? this.bannerTint).clamp(0, palettes.length - 1).toInt();
    this.bannerBlur = (bannerBlur ?? this.bannerBlur).clamp(0, 30).toDouble();
    this.bannerOpacity = (bannerOpacity ?? this.bannerOpacity).clamp(.15, .95).toDouble();
    this.bannerTop = bannerTop ?? this.bannerTop;
    this.bannerSeconds = (bannerSeconds ?? this.bannerSeconds).clamp(2, 15).toInt();
    this.bannerCompact = bannerCompact ?? this.bannerCompact;
    this.bannerMaxWidth = (bannerMaxWidth ?? this.bannerMaxWidth).clamp(280, 520).toDouble();
    this.bannerBubbles = bannerBubbles ?? this.bannerBubbles;
    this.notifyGlassAvatar = notifyGlassAvatar ?? this.notifyGlassAvatar;
    this.notifyAvatarShape = (notifyAvatarShape ?? this.notifyAvatarShape).clamp(0, 1).toInt();
    this.notifyBubbles = false;
    this.notifyQuickReply = notifyQuickReply ?? this.notifyQuickReply;
    this.notifyOtpCopy = notifyOtpCopy ?? this.notifyOtpCopy;
    if (quickReplies != null) this.quickReplies = cleanReplies(quickReplies);
    notifyListeners();
    await _saveNotify(await SharedPreferences.getInstance());
  }

  /// Trimmed, single-line, unique, at most five answers of up to 60 characters.
  static List<String> cleanReplies(Iterable<String> items) {
    final seen = <String>{};
    return [
      for (final r in items.map((e) => e.replaceAll('\n', ' ').trim()))
        if (r.isNotEmpty && r.length <= 60 && seen.add(r)) r,
    ].take(5).toList();
  }

  Future<void> _saveNotify(SharedPreferences p) async {
    await p.setBool('notifyInApp', notifyInApp);
    await p.setInt('bannerStyle', bannerStyle.index);
    await p.setInt('bannerTint', bannerTint);
    await p.setDouble('bannerBlur', bannerBlur);
    await p.setDouble('bannerOpacity', bannerOpacity);
    await p.setBool('bannerTop', bannerTop);
    await p.setInt('bannerSeconds', bannerSeconds);
    await p.setBool('bannerCompact', bannerCompact);
    await p.setDouble('bannerMaxWidth', bannerMaxWidth);
    await p.setBool('bannerBubbles', bannerBubbles);
    await p.setBool('notifyGlassAvatar', notifyGlassAvatar);
    await p.setInt('notifyAvatarShape', notifyAvatarShape);
    await p.setBool('notifyBubbles', false);
    await p.setBool('notifyQuickReply', notifyQuickReply);
    await p.setBool('notifyOtpCopy', notifyOtpCopy);
    await p.setString('notifyQuickReplies', quickReplies.join('\n'));
    await p.setInt('notifyAccent', bannerColor.toARGB32());
  }

  Map<String, Object> notifyJson() => {
    'notifyInApp': notifyInApp, 'bannerStyle': bannerStyle.index, 'bannerTint': bannerTint,
    'bannerBlur': bannerBlur, 'bannerOpacity': bannerOpacity, 'bannerTop': bannerTop,
    'bannerSeconds': bannerSeconds, 'bannerCompact': bannerCompact,
    'bannerMaxWidth': bannerMaxWidth, 'bannerBubbles': bannerBubbles, 'notifyGlassAvatar': notifyGlassAvatar,
    'notifyAvatarShape': notifyAvatarShape, 'notifyBubbles': notifyBubbles,
    'notifyQuickReply': notifyQuickReply, 'notifyOtpCopy': notifyOtpCopy, 'quickReplies': quickReplies,
  };

  Future<void> _restoreNotify(Map<String, dynamic> j) async {
    bool? b(String k) => j[k] is bool ? j[k] as bool : null;
    int? i(String k) => j[k] is num ? (j[k] as num).toInt() : null;
    double? d(String k) => j[k] is num ? (j[k] as num).toDouble() : null;
    final style = i('bannerStyle');
    final replies = j['quickReplies'];
    await updateNotify(
      notifyInApp: b('notifyInApp'),
      bannerStyle: style == null ? null : BannerStyle.values[style.clamp(0, BannerStyle.values.length - 1).toInt()],
      bannerTint: i('bannerTint'), bannerBlur: d('bannerBlur'), bannerOpacity: d('bannerOpacity'),
      bannerTop: b('bannerTop'), bannerSeconds: i('bannerSeconds'),
      bannerCompact: b('bannerCompact'), bannerMaxWidth: d('bannerMaxWidth'),
      bannerBubbles: b('bannerBubbles'),
      notifyGlassAvatar: b('notifyGlassAvatar'), notifyAvatarShape: i('notifyAvatarShape'),
      notifyBubbles: b('notifyBubbles'), notifyQuickReply: b('notifyQuickReply'), notifyOtpCopy: b('notifyOtpCopy'),
      quickReplies: replies is List ? [for (final r in replies) if (r is String) r] : null,
    );
  }

  /// Text actually sent: the user's message plus the optional signature.
  String withSignature(String text) {
    final t = text.trim();
    if (!signatureEnabled || signature.isEmpty || t.endsWith(signature)) return t;
    return '$t\n$signature';
  }

  /// Settings backup as JSON (no messages, contacts or secrets).
  Map<String, Object> toJson() => {
    'palette': palette, 'theme': mode.index, 'scale': scale, 'fontChoice': fontChoice,
    'privatePreview': hidePreview, 'notifyPreview': notifyPreview, 'notifyIncoming': notifyIncoming,
    'notifySent': notifySent, 'sentFeedback': sentFeedback.index, 'sendDelayEnabled': sendDelayEnabled,
    'sendDelaySeconds': sendDelaySeconds, 'enterToSend': enterToSend, 'signatureEnabled': signatureEnabled,
    'signature': signature, 'smartReplies': smartReplies, 'recipientCapacity': recipientCapacity, 'swipeTabs': swipeTabs,
     'reduceEffects': reduceEffects, 'chatStyle': chatStyle.index,
    'bubbleText': bubbleText, 'quietHours': quietHours, 'quietStart': quietStart, 'quietEnd': quietEnd,
    ...notifyJson(),
  };

  /// Restores a backup made by [toJson]; unknown or malformed values are ignored.
  Future<void> restore(Map<String, dynamic> j) async {
    T? v<T>(String k) => j[k] is T ? j[k] as T : null;
    int? i(String k) => (j[k] is num) ? (j[k] as num).toInt() : null;
    double? d(String k) => (j[k] is num) ? (j[k] as num).toDouble() : null;
    await update(
      palette: i('palette')?.clamp(0, palettes.length - 1).toInt(),
      mode: i('theme') == null ? null : ThemeMode.values[i('theme')!.clamp(0, 2).toInt()],
      scale: d('scale')?.clamp(.9, 1.5).toDouble(),
      fontChoice: i('fontChoice')?.clamp(0, 2).toInt(),
      hidePreview: v<bool>('privatePreview'), notifyPreview: v<bool>('notifyPreview'),
      notifyIncoming: v<bool>('notifyIncoming'), notifySent: v<bool>('notifySent'),
      sentFeedback: i('sentFeedback') == null ? null
          : SentFeedback.values[i('sentFeedback')!.clamp(0, SentFeedback.values.length - 1).toInt()],
      sendDelayEnabled: v<bool>('sendDelayEnabled'), sendDelaySeconds: i('sendDelaySeconds'),
      enterToSend: v<bool>('enterToSend'), signatureEnabled: v<bool>('signatureEnabled'),
      signature: v<String>('signature'), smartReplies: v<bool>('smartReplies'),
       recipientCapacity: i('recipientCapacity'), swipeTabs: v<bool>('swipeTabs'),
       reduceEffects: v<bool>('reduceEffects'),
      chatStyle: i('chatStyle') == null ? null
          : ChatStyle.values[i('chatStyle')!.clamp(0, ChatStyle.values.length - 1).toInt()],
      bubbleText: d('bubbleText')?.clamp(13, 20).toDouble(),
      quietHours: v<bool>('quietHours'), quietStart: i('quietStart')?.clamp(0, 1439).toInt(),
      quietEnd: i('quietEnd')?.clamp(0, 1439).toInt(),
    );
    await _restoreNotify(j);
  }

  String exportText() => const JsonEncoder.withIndent('  ').convert({'payamyar_settings': 1, ...toJson()});
}
