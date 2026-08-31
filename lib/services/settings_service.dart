import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// Theme mode values stored in preferences.
enum AppThemeMode { system, light, dark }

/// Manages application settings backed by SharedPreferences.
///
/// Notifies listeners when any setting changes.
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static Future<SettingsService> create() async {
    final service = SettingsService._();
    await service._load();
    return service;
  }

  late SharedPreferences _prefs;

  bool _vibration = true;
  bool _sound = false;
  AppThemeMode _themeMode = AppThemeMode.system;
  int _defaultTarget = kDefaultTarget;

  bool get vibration => _vibration;
  bool get sound => _sound;
  AppThemeMode get themeMode => _themeMode;
  int get defaultTarget => _defaultTarget;

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    _vibration = _prefs.getBool(kPrefVibration) ?? true;
    _sound = _prefs.getBool(kPrefSound) ?? false;
    _themeMode = AppThemeMode.values[_prefs.getInt(kPrefTheme) ?? 0];
    _defaultTarget = _prefs.getInt(kPrefDefaultTarget) ?? kDefaultTarget;
  }

  Future<void> setVibration(bool value) async {
    _vibration = value;
    await _prefs.setBool(kPrefVibration, value);
    notifyListeners();
  }

  Future<void> setSound(bool value) async {
    _sound = value;
    await _prefs.setBool(kPrefSound, value);
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt(kPrefTheme, mode.index);
    notifyListeners();
  }

  Future<void> setDefaultTarget(int target) async {
    _defaultTarget = target;
    await _prefs.setInt(kPrefDefaultTarget, target);
    notifyListeners();
  }

  /// Re-reads all settings from SharedPreferences.
  /// Call this after a backup restore writes new preference values.
  Future<void> reload() async {
    await _load();
    notifyListeners();
  }
}
