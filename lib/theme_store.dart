import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题偏好存储
class ThemeStore {
  static const _key = 'theme_mode';

  static Future<ThemeMode> load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_key);
    switch (v) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  static Future<void> save(ThemeMode m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, m == ThemeMode.light ? 'light'
        : m == ThemeMode.dark ? 'dark' : 'system');
  }
}