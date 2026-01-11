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
  final bool keepScreenOn;
  final int scrollbackLines;
  final double minFontSize;
  final bool autoFitEnabled;

  /// DirectInputモード（入力した文字を即座にターミナルに送信）
  final bool directInputEnabled;

  const AppSettings({
    this.darkMode = true,
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrains Mono',
    this.requireBiometricAuth = false,
    this.enableNotifications = true,
    this.enableVibration = true,
    this.keepScreenOn = true,
    this.scrollbackLines = 10000,
    this.minFontSize = 8.0,
    this.autoFitEnabled = true,
    this.directInputEnabled = false,
  });

  AppSettings copyWith({
    bool? darkMode,
    double? fontSize,
    String? fontFamily,
    bool? requireBiometricAuth,
    bool? enableNotifications,
    bool? enableVibration,
    bool? keepScreenOn,
    int? scrollbackLines,
    double? minFontSize,
    bool? autoFitEnabled,
    bool? directInputEnabled,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      requireBiometricAuth: requireBiometricAuth ?? this.requireBiometricAuth,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableVibration: enableVibration ?? this.enableVibration,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      minFontSize: minFontSize ?? this.minFontSize,
      autoFitEnabled: autoFitEnabled ?? this.autoFitEnabled,
      directInputEnabled: directInputEnabled ?? this.directInputEnabled,
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
  static const String _keepScreenOnKey = 'settings_keep_screen_on';
  static const String _scrollbackKey = 'settings_scrollback';
  static const String _minFontSizeKey = 'settings_min_font_size';
  static const String _autoFitEnabledKey = 'settings_auto_fit_enabled';
  static const String _directInputEnabledKey = 'settings_direct_input_enabled';

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
      keepScreenOn: prefs.getBool(_keepScreenOnKey) ?? true,
      scrollbackLines: prefs.getInt(_scrollbackKey) ?? 10000,
      minFontSize: prefs.getDouble(_minFontSizeKey) ?? 8.0,
      autoFitEnabled: prefs.getBool(_autoFitEnabledKey) ?? true,
      directInputEnabled: prefs.getBool(_directInputEnabledKey) ?? false,
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

  /// 画面常時オンを設定
  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
    await _saveSetting(_keepScreenOnKey, value);
  }

  /// スクロールバック行数を設定
  Future<void> setScrollbackLines(int value) async {
    state = state.copyWith(scrollbackLines: value);
    await _saveSetting(_scrollbackKey, value);
  }

  /// 最小フォントサイズを設定
  Future<void> setMinFontSize(double value) async {
    state = state.copyWith(minFontSize: value);
    await _saveSetting(_minFontSizeKey, value);
  }

  /// 自動フィットを設定
  Future<void> setAutoFitEnabled(bool value) async {
    state = state.copyWith(autoFitEnabled: value);
    await _saveSetting(_autoFitEnabledKey, value);
  }

  /// DirectInputモードを設定
  Future<void> setDirectInputEnabled(bool value) async {
    state = state.copyWith(directInputEnabled: value);
    await _saveSetting(_directInputEnabledKey, value);
  }

  /// DirectInputモードをトグル
  Future<void> toggleDirectInput() async {
    await setDirectInputEnabled(!state.directInputEnabled);
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
