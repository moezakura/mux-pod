import 'package:shared_preferences/shared_preferences.dart';

import '../services/settings_migration.dart';
import 'settings_state.dart';

/// SharedPreferences とのキー・型マッピング（読込・保存）とマイグレーション起動を担当する。
///
/// キー文字列は従来の `SettingsNotifier` 定義時から変更しない（40 キー完全互換）。
/// 値は bool / double / int / String のスカラー型のみで JSON 直列化は行わない。
class SettingsPersistence {
  static const String darkModeKey = 'settings_dark_mode';
  static const String fontSizeKey = 'settings_font_size';
  static const String fontFamilyKey = 'settings_font_family';
  static const String biometricKey = 'settings_biometric_auth';
  static const String notificationsKey = 'settings_notifications';
  static const String keepScreenOnKey = 'settings_keep_screen_on';
  static const String screenOrientationKey = 'settings_screen_orientation';
  static const String refreshRateKey = 'settings_refresh_rate';
  static const String scrollbackKey = 'settings_scrollback';
  static const String minFontSizeKey = 'settings_min_font_size';
  static const String zoomFactorKey = 'settings_zoom_factor';
  static const String adjustModeKey = 'settings_adjust_mode';
  static const String directInputEnabledKey = 'settings_direct_input_enabled';
  static const String cjkModeKey = 'settings_cjk_mode';
  static const String keepKeyboardOnEnterKey =
      'settings_keep_keyboard_on_enter';
  static const String showTerminalCursorKey = 'settings_show_terminal_cursor';
  // inventory: SETTINGS-HERDR-CARET-005
  static const String experimentalHerdrCaretPositionEnabledKey =
      'settings_experimental_herdr_caret_position_enabled';
  static const String invertPaneNavKey = 'settings_invert_pane_nav';
  // inventory: SETTINGS-SCROLL-SEND-004
  static const String scrollSendInputKey = 'settings_scroll_send_input';
  // inventory: SETTINGS-INVERT-SCROLL-004
  static const String invertScrollSendDirectionKey =
      'settings_invert_scroll_send_direction';
  // inventory: SETTINGS-AUTO-FIT-ZOOM-004
  static const String autoFitZoomOnScrollSendKey =
      'settings_auto_fit_zoom_on_scroll_send';
  static const String languageKey = 'settings_language';
  static const String imageRemotePathKey = 'settings_image_remote_path';
  static const String imageOutputFormatKey = 'settings_image_output_format';
  static const String imageJpegQualityKey = 'settings_image_jpeg_quality';
  static const String imageResizePresetKey = 'settings_image_resize_preset';
  static const String imageMaxWidthKey = 'settings_image_max_width';
  static const String imageMaxHeightKey = 'settings_image_max_height';
  static const String imagePathFormatKey = 'settings_image_path_format';
  static const String imageAutoEnterKey = 'settings_image_auto_enter';
  static const String imageBracketedPasteKey = 'settings_image_bracketed_paste';
  static const String showKeyOverlayKey = 'settings_show_key_overlay';
  static const String keyOverlayModifierKey = 'settings_key_overlay_modifier';
  static const String keyOverlaySpecialKey = 'settings_key_overlay_special';
  static const String keyOverlayArrowKey = 'settings_key_overlay_arrow';
  static const String keyOverlayShortcutKey = 'settings_key_overlay_shortcut';
  static const String keyOverlayPositionKey = 'settings_key_overlay_position';
  static const String uploadConflictPolicyKey =
      'settings_upload_conflict_policy';
  static const String uploadConcurrencyKey = 'settings_upload_concurrency';
  static const String uploadChunkKbKey = 'settings_upload_chunk_kb';
  // SSH キープアライブ全体設定（未設定 = 自動）。
  static const String keepAliveTimeoutKey = 'settings_keep_alive_timeout';

  /// SharedPreferences から全設定を読み込み [AppSettings] を構築する。
  ///
  /// マイグレーション（[SettingsMigrationRunner]）を読み込み前に実行する
  /// （呼び出し順は従来の `SettingsNotifier._loadSettings` と同一）。
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    await SettingsMigrationRunner.run(prefs);

    return AppSettings(
      darkMode: prefs.getBool(darkModeKey) ?? true,
      fontSize: prefs.getDouble(fontSizeKey) ?? 14.0,
      fontFamily: prefs.getString(fontFamilyKey) ?? 'JetBrains Mono',
      requireBiometricAuth: prefs.getBool(biometricKey) ?? false,
      enableNotifications: prefs.getBool(notificationsKey) ?? true,
      keepScreenOn: prefs.getBool(keepScreenOnKey) ?? true,
      screenOrientation: prefs.getString(screenOrientationKey) ?? 'portrait',
      refreshRate: prefs.getString(refreshRateKey) ?? 'auto',
      scrollbackLines: prefs.getInt(scrollbackKey) ?? 10000,
      minFontSize: prefs.getDouble(minFontSizeKey) ?? 8.0,
      zoomFactor: prefs.getDouble(zoomFactorKey) ?? 1.0,
      adjustMode: prefs.getString(adjustModeKey) ?? 'autoFit',
      directInputEnabled: prefs.getBool(directInputEnabledKey) ?? false,
      cjkMode: prefs.getBool(cjkModeKey) ?? false,
      keepKeyboardOnEnter: prefs.getBool(keepKeyboardOnEnterKey) ?? false,
      showTerminalCursor: prefs.getBool(showTerminalCursorKey) ?? true,
      // inventory: SETTINGS-HERDR-CARET-006
      experimentalHerdrCaretPositionEnabled:
          prefs.getBool(experimentalHerdrCaretPositionEnabledKey) ?? false,
      invertPaneNavigation: prefs.getBool(invertPaneNavKey) ?? false,
      // inventory: SETTINGS-SCROLL-SEND-005
      scrollSendInput: prefs.getString(scrollSendInputKey) ?? 'wheel',
      // inventory: SETTINGS-INVERT-SCROLL-005
      invertScrollSendDirection:
          prefs.getBool(invertScrollSendDirectionKey) ?? false,
      // inventory: SETTINGS-AUTO-FIT-ZOOM-005
      autoFitZoomOnScrollSend:
          prefs.getBool(autoFitZoomOnScrollSendKey) ?? false,
      language: prefs.getString(languageKey) ?? 'system',
      showKeyOverlay: prefs.getBool(showKeyOverlayKey) ?? true,
      keyOverlayModifier: prefs.getBool(keyOverlayModifierKey) ?? true,
      keyOverlaySpecial: prefs.getBool(keyOverlaySpecialKey) ?? true,
      keyOverlayArrow: prefs.getBool(keyOverlayArrowKey) ?? true,
      keyOverlayShortcut: prefs.getBool(keyOverlayShortcutKey) ?? true,
      keyOverlayPosition:
          prefs.getString(keyOverlayPositionKey) ?? 'aboveKeyboard',
      imageRemotePath: prefs.getString(imageRemotePathKey) ?? '/tmp/muxpod/',
      imageOutputFormat: prefs.getString(imageOutputFormatKey) ?? 'original',
      imageJpegQuality: prefs.getInt(imageJpegQualityKey) ?? 85,
      imageResizePreset: prefs.getString(imageResizePresetKey) ?? 'original',
      imageMaxWidth: prefs.getInt(imageMaxWidthKey) ?? 1920,
      imageMaxHeight: prefs.getInt(imageMaxHeightKey) ?? 1080,
      imagePathFormat: prefs.getString(imagePathFormatKey) ?? '{path}',
      imageAutoEnter: prefs.getBool(imageAutoEnterKey) ?? false,
      imageBracketedPaste: prefs.getBool(imageBracketedPasteKey) ?? false,
      uploadConflictPolicy: TransferConflictPolicy.fromPersisted(
        prefs.getString(uploadConflictPolicyKey),
      ),
      uploadConcurrency: prefs.getInt(uploadConcurrencyKey) ?? 2,
      uploadChunkKb: prefs.getInt(uploadChunkKbKey) ?? 256,
      // 不正値（プリセット外・型不一致）は null（自動）へフォールバック。
      keepAliveTimeoutSeconds: AppSettings.keepAliveTimeoutFromPersisted(
        prefs.get(keepAliveTimeoutKey),
      ),
    );
  }

  /// 設定値を型に応じて SharedPreferences へ保存する（bool/double/int/String のみ）。
  ///
  /// null は「未設定へ戻す」扱いでキーを削除する（例: keepalive 全体設定の
  /// 自動へ戻す）。既存の setter は null を渡さないため影響はない。
  Future<void> save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }
}
