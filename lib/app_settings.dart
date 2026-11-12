import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const brand = Color(0xFF087F81);
const palettes = [brand, Color(0xFF305F91), Color(0xFF75539A), Color(0xFF9F5369), Color(0xFF47765F), Color(0xFFA17A37)];

/// Appearance and privacy preferences.
class AppSettings extends ChangeNotifier {
  int palette = 0;
  ThemeMode mode = ThemeMode.system;
  double scale = 1;
  int fontChoice = 0; // 0 = Vazirmatn, 1 = Android default, 2 = Android serif / Naskh fallback
  bool hidePreview = false;
  bool notifyPreview = true;
  bool notifyIncoming = true;
  bool notifySent = true;

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
    notifyListeners();
  }

  Future<void> update({int? palette, ThemeMode? mode, double? scale, int? fontChoice,
      bool? hidePreview, bool? notifyPreview, bool? notifyIncoming, bool? notifySent}) async {
    this.palette = palette ?? this.palette;
    this.mode = mode ?? this.mode;
    this.scale = scale ?? this.scale;
    this.fontChoice = fontChoice ?? this.fontChoice;
    this.hidePreview = hidePreview ?? this.hidePreview;
    this.notifyPreview = notifyPreview ?? this.notifyPreview;
    this.notifyIncoming = notifyIncoming ?? this.notifyIncoming;
    this.notifySent = notifySent ?? this.notifySent;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('palette', this.palette);
    await p.setInt('theme', this.mode.index);
    await p.setDouble('scale', this.scale);
    await p.setInt('fontChoice', this.fontChoice);
    await p.setBool('privatePreview', this.hidePreview);
    // Read by the native notification code (FlutterSharedPreferences, key flutter.notifyPreview).
    await p.setBool('notifyPreview', this.notifyPreview);
    await p.setBool('notifyIncoming', this.notifyIncoming);
    await p.setBool('notifySent', this.notifySent);
  }
}
