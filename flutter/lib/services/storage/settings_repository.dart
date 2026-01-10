import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_settings.dart';
import '../../models/enums.dart';
import '../../theme/terminal_colors.dart';

/// 設定リポジトリ
///
/// アプリケーション設定の永続化を担当する。
class SettingsRepository {
  SettingsRepository({
    required SharedPreferences prefs,
  }) : _prefs = prefs;

  final SharedPreferences _prefs;

  static const _settingsKey = 'app_settings';
  static const _customColorsKey = 'custom_terminal_colors';

  /// 設定を取得
  Future<AppSettings> getSettings() async {
    final json = _prefs.getString(_settingsKey);
    if (json == null) return const AppSettings();

    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromJson(decoded);
    } catch (e) {
      return const AppSettings();
    }
  }

  /// 設定を保存
  Future<void> saveSettings(AppSettings settings) async {
    final json = jsonEncode(settings.toJson());
    await _prefs.setString(_settingsKey, json);
  }

  /// 表示設定を更新
  Future<AppSettings> updateDisplaySettings(DisplaySettings display) async {
    final settings = await getSettings();
    final updated = settings.copyWith(display: display);
    await saveSettings(updated);
    return updated;
  }

  /// ターミナル設定を更新
  Future<AppSettings> updateTerminalSettings(TerminalSettings terminal) async {
    final settings = await getSettings();
    final updated = settings.copyWith(terminal: terminal);
    await saveSettings(updated);
    return updated;
  }

  /// SSH設定を更新
  Future<AppSettings> updateSshSettings(SshSettings ssh) async {
    final settings = await getSettings();
    final updated = settings.copyWith(ssh: ssh);
    await saveSettings(updated);
    return updated;
  }

  /// セキュリティ設定を更新
  Future<AppSettings> updateSecuritySettings(SecuritySettings security) async {
    final settings = await getSettings();
    final updated = settings.copyWith(security: security);
    await saveSettings(updated);
    return updated;
  }

  /// 設定をリセット
  Future<void> resetSettings() async {
    await _prefs.remove(_settingsKey);
    await _prefs.remove(_customColorsKey);
  }

  // === カスタムカラーテーマ ===

  /// カスタムカラーを取得
  Future<TerminalColors?> getCustomColors() async {
    final json = _prefs.getString(_customColorsKey);
    if (json == null) return null;

    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return TerminalColors.fromJson(decoded);
    } catch (e) {
      return null;
    }
  }

  /// カスタムカラーを保存
  Future<void> saveCustomColors(TerminalColors colors) async {
    final json = jsonEncode(colors.toJson());
    await _prefs.setString(_customColorsKey, json);
  }

  /// 現在のテーマカラーを取得
  Future<TerminalColors> getCurrentColors() async {
    final settings = await getSettings();
    return getColorsForTheme(settings.terminal.colorTheme);
  }

  /// テーマ名からカラーを取得
  Future<TerminalColors> getColorsForTheme(ColorTheme theme) async {
    switch (theme) {
      case ColorTheme.dracula:
        return TerminalColorPresets.dracula;
      case ColorTheme.solarized:
        return TerminalColorPresets.solarizedDark;
      case ColorTheme.monokai:
        return TerminalColorPresets.monokai;
      case ColorTheme.nord:
        return TerminalColorPresets.nord;
      case ColorTheme.custom:
        return await getCustomColors() ?? TerminalColorPresets.dracula;
    }
  }

  // === 個別設定アクセス ===

  /// フォントサイズを取得
  Future<double> getFontSize() async {
    final settings = await getSettings();
    return settings.terminal.fontSize;
  }

  /// フォントサイズを設定
  Future<void> setFontSize(double size) async {
    final settings = await getSettings();
    final terminal = settings.terminal.copyWith(fontSize: size);
    await updateTerminalSettings(terminal);
  }

  /// フォントファミリーを取得
  Future<FontFamily> getFontFamily() async {
    final settings = await getSettings();
    return settings.terminal.fontFamily;
  }

  /// フォントファミリーを設定
  Future<void> setFontFamily(FontFamily family) async {
    final settings = await getSettings();
    final terminal = settings.terminal.copyWith(fontFamily: family);
    await updateTerminalSettings(terminal);
  }

  /// カラーテーマを取得
  Future<ColorTheme> getColorTheme() async {
    final settings = await getSettings();
    return settings.terminal.colorTheme;
  }

  /// カラーテーマを設定
  Future<void> setColorTheme(ColorTheme theme) async {
    final settings = await getSettings();
    final terminal = settings.terminal.copyWith(colorTheme: theme);
    await updateTerminalSettings(terminal);
  }

  /// 生体認証を取得
  Future<bool> getBiometricUnlock() async {
    final settings = await getSettings();
    return settings.security.biometricUnlock;
  }

  /// 生体認証を設定
  Future<void> setBiometricUnlock(bool enabled) async {
    final settings = await getSettings();
    final security = settings.security.copyWith(biometricUnlock: enabled);
    await updateSecuritySettings(security);
  }

  /// ダークモードを取得
  Future<bool> getDarkMode() async {
    final settings = await getSettings();
    return settings.display.darkMode;
  }

  /// ダークモードを設定
  Future<void> setDarkMode(bool enabled) async {
    final settings = await getSettings();
    final display = settings.display.copyWith(darkMode: enabled);
    await updateDisplaySettings(display);
  }
}
