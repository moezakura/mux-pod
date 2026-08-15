import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import '../services/settings_migration.dart';

/// アプリ設定
class AppSettings {
  final bool darkMode;
  final double fontSize;
  final String fontFamily;
  final bool requireBiometricAuth;
  final bool enableNotifications;
  final bool enableVibration;
  final bool keepScreenOn;

  /// 画面の向き: 'auto'（デバイスに追従）/ 'portrait' / 'landscape'
  final String screenOrientation;

  /// 最大リフレッシュレート: 'auto'（システム任せ/最高）/ '120' / '90' / '60'
  final String refreshRate;
  final int scrollbackLines;
  final double minFontSize;

  /// ピンチズーム倍率（1.0 = 等倍、永続）
  final double zoomFactor;

  /// 表示調整モード: 'none', 'autoFit', 'autoResize'
  final String adjustMode;

  /// DirectInputモード（入力した文字を即座にターミナルに送信）
  final bool directInputEnabled;

  /// ターミナルカーソルの表示設定
  final bool showTerminalCursor;

  /// ペインナビゲーション方向の反転
  final bool invertPaneNavigation;

  // --- キーオーバーレイ設定 ---
  /// キーオーバーレイ全体ON/OFF
  final bool showKeyOverlay;

  /// キーオーバーレイ: 修飾キー組み合わせ（Ctrl+x, Alt+x, Shift+x）
  final bool keyOverlayModifier;

  /// キーオーバーレイ: 単独特殊キー（ESC, TAB, ENTER, S-Enter）
  final bool keyOverlaySpecial;

  /// キーオーバーレイ: 矢印キー
  final bool keyOverlayArrow;

  /// キーオーバーレイ: ショートカットキー（/, -, 1-4）
  final bool keyOverlayShortcut;

  /// キーオーバーレイ: 表示位置
  final String keyOverlayPosition;

  // --- 画像転送設定 ---
  final String imageRemotePath;
  final String imageOutputFormat;
  final int imageJpegQuality;
  final String
  imageResizePreset; // 'original'/'small'/'medium'/'large'/'custom'
  final int imageMaxWidth;
  final int imageMaxHeight;
  final String imagePathFormat;
  final bool imageAutoEnter;
  final bool imageBracketedPaste;

  const AppSettings({
    this.darkMode = true,
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrains Mono',
    this.requireBiometricAuth = false,
    this.enableNotifications = true,
    this.enableVibration = true,
    this.keepScreenOn = true,
    this.screenOrientation = 'portrait',
    this.refreshRate = 'auto',
    this.scrollbackLines = 10000,
    this.minFontSize = 8.0,
    this.zoomFactor = 1.0,
    this.adjustMode = 'autoFit',
    this.directInputEnabled = false,
    this.showTerminalCursor = true,
    this.invertPaneNavigation = false,
    this.showKeyOverlay = true,
    this.keyOverlayModifier = true,
    this.keyOverlaySpecial = true,
    this.keyOverlayArrow = true,
    this.keyOverlayShortcut = true,
    this.keyOverlayPosition = 'aboveKeyboard',
    this.imageRemotePath = '/tmp/muxpod/',
    this.imageOutputFormat = 'original',
    this.imageJpegQuality = 85,
    this.imageResizePreset = 'original',
    this.imageMaxWidth = 1920,
    this.imageMaxHeight = 1080,
    this.imagePathFormat = '{path}',
    this.imageAutoEnter = false,
    this.imageBracketedPaste = false,
  });

  bool get isAutoFit => adjustMode == 'autoFit';
  bool get isAutoResize => adjustMode == 'autoResize';

  AppSettings copyWith({
    bool? darkMode,
    double? fontSize,
    String? fontFamily,
    bool? requireBiometricAuth,
    bool? enableNotifications,
    bool? enableVibration,
    bool? keepScreenOn,
    String? screenOrientation,
    String? refreshRate,
    int? scrollbackLines,
    double? minFontSize,
    double? zoomFactor,
    String? adjustMode,
    bool? directInputEnabled,
    bool? showTerminalCursor,
    bool? invertPaneNavigation,
    bool? showKeyOverlay,
    bool? keyOverlayModifier,
    bool? keyOverlaySpecial,
    bool? keyOverlayArrow,
    bool? keyOverlayShortcut,
    String? keyOverlayPosition,
    String? imageRemotePath,
    String? imageOutputFormat,
    int? imageJpegQuality,
    String? imageResizePreset,
    int? imageMaxWidth,
    int? imageMaxHeight,
    String? imagePathFormat,
    bool? imageAutoEnter,
    bool? imageBracketedPaste,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      requireBiometricAuth: requireBiometricAuth ?? this.requireBiometricAuth,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableVibration: enableVibration ?? this.enableVibration,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      screenOrientation: screenOrientation ?? this.screenOrientation,
      refreshRate: refreshRate ?? this.refreshRate,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      minFontSize: minFontSize ?? this.minFontSize,
      zoomFactor: zoomFactor ?? this.zoomFactor,
      adjustMode: adjustMode ?? this.adjustMode,
      directInputEnabled: directInputEnabled ?? this.directInputEnabled,
      showTerminalCursor: showTerminalCursor ?? this.showTerminalCursor,
      invertPaneNavigation: invertPaneNavigation ?? this.invertPaneNavigation,
      showKeyOverlay: showKeyOverlay ?? this.showKeyOverlay,
      keyOverlayModifier: keyOverlayModifier ?? this.keyOverlayModifier,
      keyOverlaySpecial: keyOverlaySpecial ?? this.keyOverlaySpecial,
      keyOverlayArrow: keyOverlayArrow ?? this.keyOverlayArrow,
      keyOverlayShortcut: keyOverlayShortcut ?? this.keyOverlayShortcut,
      keyOverlayPosition: keyOverlayPosition ?? this.keyOverlayPosition,
      imageRemotePath: imageRemotePath ?? this.imageRemotePath,
      imageOutputFormat: imageOutputFormat ?? this.imageOutputFormat,
      imageJpegQuality: imageJpegQuality ?? this.imageJpegQuality,
      imageResizePreset: imageResizePreset ?? this.imageResizePreset,
      imageMaxWidth: imageMaxWidth ?? this.imageMaxWidth,
      imageMaxHeight: imageMaxHeight ?? this.imageMaxHeight,
      imagePathFormat: imagePathFormat ?? this.imagePathFormat,
      imageAutoEnter: imageAutoEnter ?? this.imageAutoEnter,
      imageBracketedPaste: imageBracketedPaste ?? this.imageBracketedPaste,
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
  static const String _screenOrientationKey = 'settings_screen_orientation';
  static const String _refreshRateKey = 'settings_refresh_rate';
  static const String _scrollbackKey = 'settings_scrollback';
  static const String _minFontSizeKey = 'settings_min_font_size';
  static const String _zoomFactorKey = 'settings_zoom_factor';
  static const String _adjustModeKey = 'settings_adjust_mode';
  static const String _directInputEnabledKey = 'settings_direct_input_enabled';
  static const String _showTerminalCursorKey = 'settings_show_terminal_cursor';
  static const String _invertPaneNavKey = 'settings_invert_pane_nav';
  static const String _imageRemotePathKey = 'settings_image_remote_path';
  static const String _imageOutputFormatKey = 'settings_image_output_format';
  static const String _imageJpegQualityKey = 'settings_image_jpeg_quality';
  static const String _imageResizePresetKey = 'settings_image_resize_preset';
  static const String _imageMaxWidthKey = 'settings_image_max_width';
  static const String _imageMaxHeightKey = 'settings_image_max_height';
  static const String _imagePathFormatKey = 'settings_image_path_format';
  static const String _imageAutoEnterKey = 'settings_image_auto_enter';
  static const String _imageBracketedPasteKey =
      'settings_image_bracketed_paste';
  static const String _showKeyOverlayKey = 'settings_show_key_overlay';
  static const String _keyOverlayModifierKey = 'settings_key_overlay_modifier';
  static const String _keyOverlaySpecialKey = 'settings_key_overlay_special';
  static const String _keyOverlayArrowKey = 'settings_key_overlay_arrow';
  static const String _keyOverlayShortcutKey = 'settings_key_overlay_shortcut';
  static const String _keyOverlayPositionKey = 'settings_key_overlay_position';

  @override
  AppSettings build() {
    _loadSettings();
    return const AppSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await SettingsMigrationRunner.run(prefs);

    state = AppSettings(
      darkMode: prefs.getBool(_darkModeKey) ?? true,
      fontSize: prefs.getDouble(_fontSizeKey) ?? 14.0,
      fontFamily: prefs.getString(_fontFamilyKey) ?? 'JetBrains Mono',
      requireBiometricAuth: prefs.getBool(_biometricKey) ?? false,
      enableNotifications: prefs.getBool(_notificationsKey) ?? true,
      enableVibration: prefs.getBool(_vibrationKey) ?? true,
      keepScreenOn: prefs.getBool(_keepScreenOnKey) ?? true,
      screenOrientation: prefs.getString(_screenOrientationKey) ?? 'portrait',
      refreshRate: prefs.getString(_refreshRateKey) ?? 'auto',
      scrollbackLines: prefs.getInt(_scrollbackKey) ?? 10000,
      minFontSize: prefs.getDouble(_minFontSizeKey) ?? 8.0,
      zoomFactor: prefs.getDouble(_zoomFactorKey) ?? 1.0,
      adjustMode: prefs.getString(_adjustModeKey) ?? 'autoFit',
      directInputEnabled: prefs.getBool(_directInputEnabledKey) ?? false,
      showTerminalCursor: prefs.getBool(_showTerminalCursorKey) ?? true,
      invertPaneNavigation: prefs.getBool(_invertPaneNavKey) ?? false,
      showKeyOverlay: prefs.getBool(_showKeyOverlayKey) ?? true,
      keyOverlayModifier: prefs.getBool(_keyOverlayModifierKey) ?? true,
      keyOverlaySpecial: prefs.getBool(_keyOverlaySpecialKey) ?? true,
      keyOverlayArrow: prefs.getBool(_keyOverlayArrowKey) ?? true,
      keyOverlayShortcut: prefs.getBool(_keyOverlayShortcutKey) ?? true,
      keyOverlayPosition:
          prefs.getString(_keyOverlayPositionKey) ?? 'aboveKeyboard',
      imageRemotePath: prefs.getString(_imageRemotePathKey) ?? '/tmp/muxpod/',
      imageOutputFormat: prefs.getString(_imageOutputFormatKey) ?? 'original',
      imageJpegQuality: prefs.getInt(_imageJpegQualityKey) ?? 85,
      imageResizePreset: prefs.getString(_imageResizePresetKey) ?? 'original',
      imageMaxWidth: prefs.getInt(_imageMaxWidthKey) ?? 1920,
      imageMaxHeight: prefs.getInt(_imageMaxHeightKey) ?? 1080,
      imagePathFormat: prefs.getString(_imagePathFormatKey) ?? '{path}',
      imageAutoEnter: prefs.getBool(_imageAutoEnterKey) ?? false,
      imageBracketedPaste: prefs.getBool(_imageBracketedPasteKey) ?? false,
    );

    await _applyScreenOrientation(state.screenOrientation);
    await _applyRefreshRate(state.refreshRate);
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

  /// ピンチズーム倍率を設定（永続）
  Future<void> setZoomFactor(double value) async {
    state = state.copyWith(zoomFactor: value);
    await _saveSetting(_zoomFactorKey, value);
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

  /// 画面の向きを設定（即座に適用）
  Future<void> setScreenOrientation(String value) async {
    state = state.copyWith(screenOrientation: value);
    await _saveSetting(_screenOrientationKey, value);
    await _applyScreenOrientation(value);
  }

  /// 画面の向き設定をプラットフォームへ適用
  Future<void> _applyScreenOrientation(String value) async {
    const portrait = [DeviceOrientation.portraitUp];
    const landscape = [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    final List<DeviceOrientation> orientations;
    switch (value) {
      case 'portrait':
        // portraitUp のみ: 上下逆さま表示を防ぐ（端末アプリでは逆さUIは望ましくない）。
        // landscape は左右両方の握りを許可するのに対し、この非対称は意図的。
        orientations = portrait;
      case 'landscape':
        orientations = landscape;
      default:
        orientations = const <DeviceOrientation>[]; // すべて許可
    }
    await SystemChrome.setPreferredOrientations(orientations);
  }

  /// 最大リフレッシュレートを設定（即座に適用）
  Future<void> setRefreshRate(String value) async {
    state = state.copyWith(refreshRate: value);
    await _saveSetting(_refreshRateKey, value);
    await _applyRefreshRate(value);
  }

  /// リフレッシュレート上限をプラットフォームへ適用（Androidのみ）。
  /// 'auto' は最高レート、数値指定は「その値以下で最高」のモードを選ぶ。
  /// LTPO/ProMotion パネルや iOS では効果がないことがある（最終判断はシステム）。
  Future<void> _applyRefreshRate(String value) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      if (value == 'auto') {
        await FlutterDisplayMode.setHighRefreshRate();
        return;
      }
      final cap = double.tryParse(value);
      if (cap == null) {
        await FlutterDisplayMode.setHighRefreshRate();
        return;
      }
      final modes = await FlutterDisplayMode.supported;
      if (modes.isEmpty) {
        return;
      }
      final active = await FlutterDisplayMode.active;
      bool ok(DisplayMode m) => m.refreshRate > 0 && m.refreshRate <= cap + 0.5;
      // まず同一解像度で上限以下、無ければ全体から上限以下を選ぶ
      var pool = modes
          .where(
            (m) =>
                m.width == active.width && m.height == active.height && ok(m),
          )
          .toList();
      if (pool.isEmpty) {
        pool = modes.where(ok).toList();
      }
      if (pool.isEmpty) {
        return; // 上限以下のモードが無ければ現状維持
      }
      pool.sort((a, b) => b.refreshRate.compareTo(a.refreshRate));
      await FlutterDisplayMode.setPreferredMode(pool.first);
    } catch (_) {
      // ディスプレイモード制御が使えない端末では無視
    }
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

  /// 表示調整モードを設定
  Future<void> setAdjustMode(String value) async {
    state = state.copyWith(adjustMode: value);
    await _saveSetting(_adjustModeKey, value);
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

  /// ターミナルカーソル表示設定を設定
  Future<void> setShowTerminalCursor(bool value) async {
    state = state.copyWith(showTerminalCursor: value);
    await _saveSetting(_showTerminalCursorKey, value);
  }

  /// ペインナビゲーション方向の反転を設定
  Future<void> setInvertPaneNavigation(bool value) async {
    state = state.copyWith(invertPaneNavigation: value);
    await _saveSetting(_invertPaneNavKey, value);
  }

  // --- キーオーバーレイ設定のsetter ---
  Future<void> setShowKeyOverlay(bool value) async {
    state = state.copyWith(showKeyOverlay: value);
    await _saveSetting(_showKeyOverlayKey, value);
  }

  Future<void> setKeyOverlayModifier(bool value) async {
    state = state.copyWith(keyOverlayModifier: value);
    await _saveSetting(_keyOverlayModifierKey, value);
  }

  Future<void> setKeyOverlaySpecial(bool value) async {
    state = state.copyWith(keyOverlaySpecial: value);
    await _saveSetting(_keyOverlaySpecialKey, value);
  }

  Future<void> setKeyOverlayArrow(bool value) async {
    state = state.copyWith(keyOverlayArrow: value);
    await _saveSetting(_keyOverlayArrowKey, value);
  }

  Future<void> setKeyOverlayShortcut(bool value) async {
    state = state.copyWith(keyOverlayShortcut: value);
    await _saveSetting(_keyOverlayShortcutKey, value);
  }

  Future<void> setKeyOverlayPosition(String value) async {
    state = state.copyWith(keyOverlayPosition: value);
    await _saveSetting(_keyOverlayPositionKey, value);
  }

  // --- 画像転送設定のsetter ---
  Future<void> setImageRemotePath(String value) async {
    state = state.copyWith(imageRemotePath: value);
    await _saveSetting(_imageRemotePathKey, value);
  }

  Future<void> setImageOutputFormat(String value) async {
    state = state.copyWith(imageOutputFormat: value);
    await _saveSetting(_imageOutputFormatKey, value);
  }

  Future<void> setImageJpegQuality(int value) async {
    state = state.copyWith(imageJpegQuality: value);
    await _saveSetting(_imageJpegQualityKey, value);
  }

  Future<void> setImageResizePreset(String value) async {
    state = state.copyWith(imageResizePreset: value);
    await _saveSetting(_imageResizePresetKey, value);
  }

  Future<void> setImageMaxWidth(int value) async {
    state = state.copyWith(imageMaxWidth: value);
    await _saveSetting(_imageMaxWidthKey, value);
  }

  Future<void> setImageMaxHeight(int value) async {
    state = state.copyWith(imageMaxHeight: value);
    await _saveSetting(_imageMaxHeightKey, value);
  }

  Future<void> setImagePathFormat(String value) async {
    state = state.copyWith(imagePathFormat: value);
    await _saveSetting(_imagePathFormatKey, value);
  }

  Future<void> setImageAutoEnter(bool value) async {
    state = state.copyWith(imageAutoEnter: value);
    await _saveSetting(_imageAutoEnterKey, value);
  }

  Future<void> setImageBracketedPaste(bool value) async {
    state = state.copyWith(imageBracketedPaste: value);
    await _saveSetting(_imageBracketedPasteKey, value);
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
