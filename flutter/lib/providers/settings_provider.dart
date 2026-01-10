import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/enums.dart';
import '../services/storage/settings_repository.dart';
import '../theme/terminal_colors.dart';
import 'connection_provider.dart';

/// SettingsRepository プロバイダー
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return SettingsRepository(prefs: storageService.prefs);
});

/// アプリ設定プロバイダー
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

/// アプリ設定Notifier
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    return await _repository.getSettings();
  }

  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  /// 設定全体を更新
  Future<void> updateSettings(AppSettings settings) async {
    await _repository.saveSettings(settings);
    state = AsyncValue.data(settings);
  }

  /// 表示設定を更新
  Future<void> updateDisplaySettings(DisplaySettings display) async {
    final updated = await _repository.updateDisplaySettings(display);
    state = AsyncValue.data(updated);
  }

  /// ターミナル設定を更新
  Future<void> updateTerminalSettings(TerminalSettings terminal) async {
    final updated = await _repository.updateTerminalSettings(terminal);
    state = AsyncValue.data(updated);
  }

  /// SSH設定を更新
  Future<void> updateSshSettings(SshSettings ssh) async {
    final updated = await _repository.updateSshSettings(ssh);
    state = AsyncValue.data(updated);
  }

  /// セキュリティ設定を更新
  Future<void> updateSecuritySettings(SecuritySettings security) async {
    final updated = await _repository.updateSecuritySettings(security);
    state = AsyncValue.data(updated);
  }

  /// 設定をリセット
  Future<void> resetSettings() async {
    await _repository.resetSettings();
    state = const AsyncValue.data(AppSettings());
  }

  // === 個別設定 ===

  /// フォントサイズ変更
  Future<void> setFontSize(double size) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final terminal = current.terminal.copyWith(fontSize: size);
    await updateTerminalSettings(terminal);
  }

  /// フォントファミリー変更
  Future<void> setFontFamily(FontFamily family) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final terminal = current.terminal.copyWith(fontFamily: family);
    await updateTerminalSettings(terminal);
  }

  /// カラーテーマ変更
  Future<void> setColorTheme(ColorTheme theme) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final terminal = current.terminal.copyWith(colorTheme: theme);
    await updateTerminalSettings(terminal);
  }

  /// ダークモード変更
  Future<void> setDarkMode(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final display = current.display.copyWith(darkMode: enabled);
    await updateDisplaySettings(display);
  }

  /// 生体認証変更
  Future<void> setBiometricUnlock(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final security = current.security.copyWith(biometricUnlock: enabled);
    await updateSecuritySettings(security);
  }

  /// 画面常時点灯変更
  Future<void> setKeepScreenOn(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final display = current.display.copyWith(keepScreenOn: enabled);
    await updateDisplaySettings(display);
  }

  /// 特殊キーバー表示変更
  Future<void> setShowSpecialKeysBar(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final terminal = current.terminal.copyWith(showSpecialKeysBar: enabled);
    await updateTerminalSettings(terminal);
  }
}

// === 派生プロバイダー ===

/// 表示設定プロバイダー
final displaySettingsProvider = Provider<DisplaySettings>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.maybeWhen(
    data: (s) => s.display,
    orElse: () => const DisplaySettings(),
  );
});

/// ターミナル設定プロバイダー
final terminalSettingsProvider = Provider<TerminalSettings>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.maybeWhen(
    data: (s) => s.terminal,
    orElse: () => const TerminalSettings(),
  );
});

/// SSH設定プロバイダー
final sshSettingsProvider = Provider<SshSettings>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.maybeWhen(
    data: (s) => s.ssh,
    orElse: () => const SshSettings(),
  );
});

/// セキュリティ設定プロバイダー
final securitySettingsProvider = Provider<SecuritySettings>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.maybeWhen(
    data: (s) => s.security,
    orElse: () => const SecuritySettings(),
  );
});

/// 現在のターミナルカラープロバイダー
final terminalColorsProvider = FutureProvider<TerminalColors>((ref) async {
  final repository = ref.watch(settingsRepositoryProvider);
  return await repository.getCurrentColors();
});

/// テーマモードプロバイダー
final themeModeProvider = Provider<ThemeMode>((ref) {
  final display = ref.watch(displaySettingsProvider);

  if (display.useSystemTheme) {
    return ThemeMode.system;
  }
  return display.darkMode ? ThemeMode.dark : ThemeMode.light;
});

/// フォントサイズプロバイダー
final fontSizeProvider = Provider<double>((ref) {
  final terminal = ref.watch(terminalSettingsProvider);
  return terminal.fontSize;
});

/// フォントファミリープロバイダー
final fontFamilyProvider = Provider<FontFamily>((ref) {
  final terminal = ref.watch(terminalSettingsProvider);
  return terminal.fontFamily;
});

/// カラーテーマプロバイダー
final colorThemeProvider = Provider<ColorTheme>((ref) {
  final terminal = ref.watch(terminalSettingsProvider);
  return terminal.colorTheme;
});

/// 生体認証有効プロバイダー
final biometricUnlockProvider = Provider<bool>((ref) {
  final security = ref.watch(securitySettingsProvider);
  return security.biometricUnlock;
});

/// 画面常時点灯プロバイダー
final keepScreenOnProvider = Provider<bool>((ref) {
  final display = ref.watch(displaySettingsProvider);
  return display.keepScreenOn;
});

/// 特殊キーバー表示プロバイダー
final showSpecialKeysBarProvider = Provider<bool>((ref) {
  final terminal = ref.watch(terminalSettingsProvider);
  return terminal.showSpecialKeysBar;
});
