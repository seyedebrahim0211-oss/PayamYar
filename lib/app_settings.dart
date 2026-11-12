import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const brand = Color(0xFF087F81);
const palettes = [brand, Color(0xFF305F91), Color(0xFF75539A), Color(0xFF9F5369), Color(0xFF47765F), Color(0xFFA17A37)];

/// Appearance and privacy preferences.
class AppSettings extends ChangeNotifier {
  int palette = 0;
  ThemeMode mode = ThemeMode.system;
  double scale = 1;
  bool hidePreview = false;
  bool notifyPreview = true;
  bool notifyIncoming = true;
  bool notifySent = true;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    palette = (p.getInt('palette') ?? 0).clamp(0, palettes.length - 1).toInt();
    mode = ThemeMode.values[(p.getInt('theme') ?? 0).clamp(0, 2).toInt()];
    scale = (p.getDouble('scale') ?? 1).clamp(.85, 1.3).toDouble();
    hidePreview = p.getBool('privatePreview') ?? false;
    notifyPreview = p.getBool('notifyPreview') ?? true;
    notifyIncoming = p.getBool('notifyIncoming') ?? true;
    notifySent = p.getBool('notifySent') ?? true;
    notifyListeners();
  }

  Future<void> update({int? palette, ThemeMode? mode, double? scale,
      bool? hidePreview, bool? notifyPreview, bool? notifyIncoming, bool? notifySent}) async {
    this.palette = palette ?? this.palette;
    this.mode = mode ?? this.mode;
    this.scale = scale ?? this.scale;
    this.hidePreview = hidePreview ?? this.hidePreview;
    this.notifyPreview = notifyPreview ?? this.notifyPreview;
    this.notifyIncoming = notifyIncoming ?? this.notifyIncoming;
    this.notifySent = notifySent ?? this.notifySent;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('palette', this.palette);
    await p.setInt('theme', this.mode.index);
    await p.setDouble('scale', this.scale);
    await p.setBool('privatePreview', this.hidePreview);
    // Read by the native notification code (FlutterSharedPreferences, key flutter.notifyPreview).
    await p.setBool('notifyPreview', this.notifyPreview);
    await p.setBool('notifyIncoming', this.notifyIncoming);
    await p.setBool('notifySent', this.notifySent);
  }
}
