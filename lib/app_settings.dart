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

/// Appearance, sending and privacy preferences.
class AppSettings extends ChangeNotifier {
  int palette = 0;
  ThemeMode mode = ThemeMode.system;
  double scale = 1;
  int fontChoice = 0; // 0 = Vazirmatn, 1 = Android default, 2 = Android serif / Naskh fallback
  bool hidePreview = false;
  bool notifyPreview = true;
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

  // ── chat look ──
  ChatStyle chatStyle = ChatStyle.traditional;
  double bubbleText = 15.5;

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
    hidePreview = p.getBool('privatePreview') ?? false;
    notifyPreview = p.getBool('notifyPreview') ?? true;
    notifyIncoming = p.getBool('notifyIncoming') ?? true;
    notifySent = p.getBool('notifySent') ?? true;
    sendDelayEnabled = p.getBool('sendDelayEnabled') ?? true;
    sendDelaySeconds = (p.getInt('sendDelaySeconds') ?? 5).clamp(1, 10).toInt();
    sentFeedback = SentFeedback.values[(p.getInt('sentFeedback') ?? 0).clamp(0, SentFeedback.values.length - 1).toInt()];
    enterToSend = p.getBool('enterToSend') ?? false;
    signatureEnabled = p.getBool('signatureEnabled') ?? false;
    signature = p.getString('signature') ?? '';
    smartReplies = p.getBool('smartReplies') ?? true;
    chatStyle = ChatStyle.values[(p.getInt('chatStyle') ?? 0).clamp(0, ChatStyle.values.length - 1).toInt()];
    bubbleText = (p.getDouble('bubbleText') ?? 15.5).clamp(13, 20).toDouble();
    quietHours = p.getBool('quietHours') ?? false;
    quietStart = (p.getInt('quietStart') ?? 23 * 60).clamp(0, 1439).toInt();
    quietEnd = (p.getInt('quietEnd') ?? 7 * 60).clamp(0, 1439).toInt();
    notifyListeners();
  }

  Future<void> update({int? palette, ThemeMode? mode, double? scale, int? fontChoice,
      bool? hidePreview, bool? notifyPreview, bool? notifyIncoming, bool? notifySent,
      bool? sendDelayEnabled, int? sendDelaySeconds, SentFeedback? sentFeedback, bool? enterToSend,
      bool? signatureEnabled, String? signature, bool? smartReplies, ChatStyle? chatStyle,
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
    await p.setInt('chatStyle', chatStyle.index);
    await p.setDouble('bubbleText', bubbleText);
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
    'signature': signature, 'smartReplies': smartReplies, 'chatStyle': chatStyle.index,
    'bubbleText': bubbleText, 'quietHours': quietHours, 'quietStart': quietStart, 'quietEnd': quietEnd,
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
      chatStyle: i('chatStyle') == null ? null
          : ChatStyle.values[i('chatStyle')!.clamp(0, ChatStyle.values.length - 1).toInt()],
      bubbleText: d('bubbleText')?.clamp(13, 20).toDouble(),
      quietHours: v<bool>('quietHours'), quietStart: i('quietStart')?.clamp(0, 1439).toInt(),
      quietEnd: i('quietEnd')?.clamp(0, 1439).toInt(),
    );
  }

  String exportText() => const JsonEncoder.withIndent('  ').convert({'payamyar_settings': 1, ...toJson()});
}
