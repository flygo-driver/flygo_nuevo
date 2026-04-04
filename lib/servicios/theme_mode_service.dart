import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeService {
  ThemeModeService._();

  static const String _kThemeModeKey = 'app_theme_mode';
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeModeKey) ?? 'dark';
    mode.value = _parse(raw);
  }

  static Future<void> setMode(ThemeMode next) async {
    if (mode.value == next) return;
    mode.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, _encode(next));
  }

  static Future<void> toggleLightDark() async {
    final next = mode.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setMode(next);
  }

  static ThemeMode _parse(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.dark:
        return 'dark';
    }
  }
}
