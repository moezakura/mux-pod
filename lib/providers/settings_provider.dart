import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ設定
class AppSettings {
  final bool darkMode;
  final double fontSize;
  final String fontFamily;
  final bool requireBiometricAuth;
  final bool enableNotifications;
  final bool enableVibration;
  final int scrollbackLines;

  const AppSettings({
    this.darkMode = true,
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrains Mono',
    this.requireBiometricAuth = false,
    this.enableNotifications = true,
    this.enableVibration = true,
    this.scrollbackLines = 10000,
  });

  AppSettings copyWith({
    bool? darkMode,
    double? fontSize,
    String? fontFamily,
    bool? requireBiometricAuth,
    bool? enableNotifications,
    bool? enableVibration,
    int? scrollbackLines,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      requireBiometricAuth: requireBiometricAuth ?? this.requireBiometricAuth,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableVibration: enableVibration ?? this.enableVibration,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
    );
  }
}

/// 設定を管理するNotifier
class SettingsNotifier extends Notifier<AppSettings> {
  static const String _darkModeKey = 'settings_dark_mode';
  static const String _fontSizeKey = 'settings_font_size';
  static const String _fontFamilyKey = 'settings_font_family';
  static const String _biometricKey = 'settings_biometric_auth';
  static const String _notificationsKey = 'settings_notifications';
  static const String _vibrationKey = 'settings_vibration';
  static const String _scrollbackKey = 'settings_scrollback';

  @override
  AppSettings build() {
    _loadSettings();
    return const AppSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    state = AppSettings(
      darkMode: prefs.getBool(_darkModeKey) ?? true,
      fontSize: prefs.getDouble(_fontSizeKey) ?? 14.0,
      fontFamily: prefs.getString(_fontFamilyKey) ?? 'JetBrains Mono',
      requireBiometricAuth: prefs.getBool(_biometricKey) ?? false,
      enableNotifications: prefs.getBool(_notificationsKey) ?? true,
      enableVibration: prefs.getBool(_vibrationKey) ?? true,
      scrollbackLines: prefs.getInt(_scrollbackKey) ?? 10000,
    );
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  /// ダークモードを設定
  Future<void> setDarkMode(bool value) async {
    state = state.copyWith(darkMode: value);
    await _saveSetting(_darkModeKey, value);
  }

  /// フォントサイズを設定
  Future<void> setFontSize(double value) async {
    state = state.copyWith(fontSize: value);
    await _saveSetting(_fontSizeKey, value);
  }

  /// フォントファミリーを設定
  Future<void> setFontFamily(String value) async {
    state = state.copyWith(fontFamily: value);
    await _saveSetting(_fontFamilyKey, value);
  }

  /// 生体認証を設定
  Future<void> setRequireBiometricAuth(bool value) async {
    state = state.copyWith(requireBiometricAuth: value);
    await _saveSetting(_biometricKey, value);
  }

  /// 通知を設定
  Future<void> setEnableNotifications(bool value) async {
    state = state.copyWith(enableNotifications: value);
    await _saveSetting(_notificationsKey, value);
  }

  /// バイブレーションを設定
  Future<void> setEnableVibration(bool value) async {
    state = state.copyWith(enableVibration: value);
    await _saveSetting(_vibrationKey, value);
  }

  /// スクロールバック行数を設定
  Future<void> setScrollbackLines(int value) async {
    state = state.copyWith(scrollbackLines: value);
    await _saveSetting(_scrollbackKey, value);
  }

  /// リロード
  Future<void> reload() async {
    await _loadSettings();
  }
}

/// 設定プロバイダー
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

/// ダークモードプロバイダー（便利アクセス）
final darkModeProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).darkMode;
});
