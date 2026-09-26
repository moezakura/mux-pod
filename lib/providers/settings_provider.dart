import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_lookup.dart';
import 'settings_persistence.dart';
import 'settings_platform_applier.dart';
import 'settings_state.dart';

export 'settings_state.dart';

/// 設定を管理するNotifier
class SettingsNotifier extends Notifier<AppSettings> {
  /// SharedPreferences への読込・保存（キー・型マッピング・マイグレーション起動）。
  final SettingsPersistence _persistence = SettingsPersistence();

  /// 設定値の OS/デバイス適用（向き・リフレッシュレート）。
  final SettingsPlatformApplier _applier = SettingsPlatformApplier();

  @override
  AppSettings build() {
    _loadSettings();
    return const AppSettings();
  }

  Future<void> _loadSettings() async {
    final loaded = await _persistence.load();

    // コンテナ破棄後の state 更新を防止する (テスト等で async ギャップ後に破棄されるケース)。
    if (!ref.mounted) return;

    state = loaded;

    // 言語設定を l10n キャッシュへ反映（BuildContext を持たない層用）。
    setCachedLanguage(state.language);

    await _applier.applyOrientation(state.screenOrientation);
    await _applier.applyRefreshRate(state.refreshRate);
  }

  /// ダークモードを設定
  Future<void> setDarkMode(bool value) async {
    state = state.copyWith(darkMode: value);
    await _persistence.save(SettingsPersistence.darkModeKey, value);
  }

  /// フォントサイズを設定
  Future<void> setFontSize(double value) async {
    state = state.copyWith(fontSize: value);
    await _persistence.save(SettingsPersistence.fontSizeKey, value);
  }

  /// ピンチズーム倍率を設定（永続）
  Future<void> setZoomFactor(double value) async {
    state = state.copyWith(zoomFactor: value);
    await _persistence.save(SettingsPersistence.zoomFactorKey, value);
  }

  /// フォントファミリーを設定
  Future<void> setFontFamily(String value) async {
    state = state.copyWith(fontFamily: value);
    await _persistence.save(SettingsPersistence.fontFamilyKey, value);
  }

  /// 生体認証を設定
  Future<void> setRequireBiometricAuth(bool value) async {
    state = state.copyWith(requireBiometricAuth: value);
    await _persistence.save(SettingsPersistence.biometricKey, value);
  }

  /// 通知を設定
  Future<void> setEnableNotifications(bool value) async {
    state = state.copyWith(enableNotifications: value);
    await _persistence.save(SettingsPersistence.notificationsKey, value);
  }

  /// 画面常時オンを設定
  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
    await _persistence.save(SettingsPersistence.keepScreenOnKey, value);
  }

  /// 画面の向きを設定（即座に適用）
  Future<void> setScreenOrientation(String value) async {
    state = state.copyWith(screenOrientation: value);
    await _persistence.save(SettingsPersistence.screenOrientationKey, value);
    await _applier.applyOrientation(value);
  }

  /// 最大リフレッシュレートを設定（即座に適用）
  Future<void> setRefreshRate(String value) async {
    state = state.copyWith(refreshRate: value);
    await _persistence.save(SettingsPersistence.refreshRateKey, value);
    await _applier.applyRefreshRate(value);
  }

  /// スクロールバック行数を設定
  Future<void> setScrollbackLines(int value) async {
    state = state.copyWith(scrollbackLines: value);
    await _persistence.save(SettingsPersistence.scrollbackKey, value);
  }

  /// 最小フォントサイズを設定
  Future<void> setMinFontSize(double value) async {
    state = state.copyWith(minFontSize: value);
    await _persistence.save(SettingsPersistence.minFontSizeKey, value);
  }

  /// 表示調整モードを設定
  Future<void> setAdjustMode(String value) async {
    state = state.copyWith(adjustMode: value);
    await _persistence.save(SettingsPersistence.adjustModeKey, value);
  }

  /// DirectInputモードを設定
  Future<void> setDirectInputEnabled(bool value) async {
    state = state.copyWith(directInputEnabled: value);
    await _persistence.save(SettingsPersistence.directInputEnabledKey, value);
  }

  /// DirectInputモードをトグル
  Future<void> toggleDirectInput() async {
    await setDirectInputEnabled(!state.directInputEnabled);
  }

  /// CJK Mode（IME確定ごとに送信してクリアする旧来のDirectInput挙動）を設定
  Future<void> setCjkMode(bool value) async {
    state = state.copyWith(cjkMode: value);
    await _persistence.save(SettingsPersistence.cjkModeKey, value);
  }

  /// Enter送信後もソフトウェアキーボードを開いたままにする
  Future<void> setKeepKeyboardOnEnter(bool value) async {
    state = state.copyWith(keepKeyboardOnEnter: value);
    await _persistence.save(SettingsPersistence.keepKeyboardOnEnterKey, value);
  }

  /// ターミナルカーソル表示設定を設定
  Future<void> setShowTerminalCursor(bool value) async {
    state = state.copyWith(showTerminalCursor: value);
    await _persistence.save(SettingsPersistence.showTerminalCursorKey, value);
  }

  /// 実験的: Herdrカーソル位置スナップショット取得を設定
  // inventory: SETTINGS-HERDR-CARET-007
  Future<void> setExperimentalHerdrCaretPositionEnabled(bool value) async {
    state = state.copyWith(experimentalHerdrCaretPositionEnabled: value);
    await _persistence.save(
      SettingsPersistence.experimentalHerdrCaretPositionEnabledKey,
      value,
    );
  }

  /// ペインナビゲーション方向の反転を設定
  Future<void> setInvertPaneNavigation(bool value) async {
    state = state.copyWith(invertPaneNavigation: value);
    await _persistence.save(SettingsPersistence.invertPaneNavKey, value);
  }

  /// スクロール送信の送信方式を設定（'wheel' / 'key'）
  // inventory: SETTINGS-SCROLL-SEND-006
  Future<void> setScrollSendInput(String value) async {
    state = state.copyWith(scrollSendInput: value);
    await _persistence.save(SettingsPersistence.scrollSendInputKey, value);
  }

  /// スクロール送信方向の反転を設定
  // inventory: SETTINGS-INVERT-SCROLL-006
  Future<void> setInvertScrollSendDirection(bool value) async {
    state = state.copyWith(invertScrollSendDirection: value);
    await _persistence.save(
      SettingsPersistence.invertScrollSendDirectionKey,
      value,
    );
  }

  /// スクロール送信モード中の自動フィットズームを設定
  // inventory: SETTINGS-AUTO-FIT-ZOOM-006
  Future<void> setAutoFitZoomOnScrollSend(bool value) async {
    state = state.copyWith(autoFitZoomOnScrollSend: value);
    await _persistence.save(
      SettingsPersistence.autoFitZoomOnScrollSendKey,
      value,
    );
  }

  /// 表示言語を設定（'system' / 'ja' / 'en'）
  Future<void> setLanguage(String value) async {
    state = state.copyWith(language: value);
    setCachedLanguage(value);
    await _persistence.save(SettingsPersistence.languageKey, value);
  }

  // --- キーオーバーレイ設定のsetter ---
  Future<void> setShowKeyOverlay(bool value) async {
    state = state.copyWith(showKeyOverlay: value);
    await _persistence.save(SettingsPersistence.showKeyOverlayKey, value);
  }

  Future<void> setKeyOverlayModifier(bool value) async {
    state = state.copyWith(keyOverlayModifier: value);
    await _persistence.save(SettingsPersistence.keyOverlayModifierKey, value);
  }

  Future<void> setKeyOverlaySpecial(bool value) async {
    state = state.copyWith(keyOverlaySpecial: value);
    await _persistence.save(SettingsPersistence.keyOverlaySpecialKey, value);
  }

  Future<void> setKeyOverlayArrow(bool value) async {
    state = state.copyWith(keyOverlayArrow: value);
    await _persistence.save(SettingsPersistence.keyOverlayArrowKey, value);
  }

  Future<void> setKeyOverlayShortcut(bool value) async {
    state = state.copyWith(keyOverlayShortcut: value);
    await _persistence.save(SettingsPersistence.keyOverlayShortcutKey, value);
  }

  Future<void> setKeyOverlayPosition(String value) async {
    state = state.copyWith(keyOverlayPosition: value);
    await _persistence.save(SettingsPersistence.keyOverlayPositionKey, value);
  }

  // --- 画像転送設定のsetter ---
  Future<void> setImageRemotePath(String value) async {
    state = state.copyWith(imageRemotePath: value);
    await _persistence.save(SettingsPersistence.imageRemotePathKey, value);
  }

  Future<void> setImageOutputFormat(String value) async {
    state = state.copyWith(imageOutputFormat: value);
    await _persistence.save(SettingsPersistence.imageOutputFormatKey, value);
  }

  Future<void> setImageJpegQuality(int value) async {
    state = state.copyWith(imageJpegQuality: value);
    await _persistence.save(SettingsPersistence.imageJpegQualityKey, value);
  }

  Future<void> setImageResizePreset(String value) async {
    state = state.copyWith(imageResizePreset: value);
    await _persistence.save(SettingsPersistence.imageResizePresetKey, value);
  }

  Future<void> setImageMaxWidth(int value) async {
    state = state.copyWith(imageMaxWidth: value);
    await _persistence.save(SettingsPersistence.imageMaxWidthKey, value);
  }

  Future<void> setImageMaxHeight(int value) async {
    state = state.copyWith(imageMaxHeight: value);
    await _persistence.save(SettingsPersistence.imageMaxHeightKey, value);
  }

  Future<void> setImagePathFormat(String value) async {
    state = state.copyWith(imagePathFormat: value);
    await _persistence.save(SettingsPersistence.imagePathFormatKey, value);
  }

  Future<void> setImageAutoEnter(bool value) async {
    state = state.copyWith(imageAutoEnter: value);
    await _persistence.save(SettingsPersistence.imageAutoEnterKey, value);
  }

  Future<void> setImageBracketedPaste(bool value) async {
    state = state.copyWith(imageBracketedPaste: value);
    await _persistence.save(SettingsPersistence.imageBracketedPasteKey, value);
  }

  // --- ファイル転送設定（#41）のsetter ---
  /// ファイル名衝突ポリシーを設定
  Future<void> setUploadConflictPolicy(TransferConflictPolicy value) async {
    state = state.copyWith(uploadConflictPolicy: value);
    await _persistence.save(
      SettingsPersistence.uploadConflictPolicyKey,
      value.persistedValue,
    );
  }

  /// 同時アップロード並列数を設定（1〜8 に制限）
  Future<void> setUploadConcurrency(int value) async {
    final clamped = value.clamp(1, 8);
    state = state.copyWith(uploadConcurrency: clamped);
    await _persistence.save(SettingsPersistence.uploadConcurrencyKey, clamped);
  }

  /// アップロード書き込みチャンクサイズ（KB）を設定（16〜8192 に制限）
  Future<void> setUploadChunkKb(int value) async {
    final clamped = value.clamp(16, 8192);
    state = state.copyWith(uploadChunkKb: clamped);
    await _persistence.save(SettingsPersistence.uploadChunkKbKey, clamped);
  }

  /// SSH キープアライブのプローブタイムアウト（秒）を設定（null = 自動）。
  ///
  /// null で呼ぶと SharedPreferences のキーを削除し、状態も未設定（自動）へ戻す。
  Future<void> setKeepAliveTimeoutSeconds(int? value) async {
    state = state.copyWith(
      keepAliveTimeoutSeconds: value,
      clearKeepAliveTimeout: value == null,
    );
    await _persistence.save(SettingsPersistence.keepAliveTimeoutKey, value);
  }

  Future<void> setBackgroundMode(
    NetworkKind network,
    BackgroundMode mode,
  ) async {
    final key = switch (network) {
      NetworkKind.mobile => SettingsPersistence.mobileBackgroundModeKey,
      NetworkKind.wifi => SettingsPersistence.wifiBackgroundModeKey,
      NetworkKind.unknown => SettingsPersistence.unknownBackgroundModeKey,
    };
    state = state.copyWith(
      mobileBackgroundMode: network == NetworkKind.mobile ? mode : null,
      wifiBackgroundMode: network == NetworkKind.wifi ? mode : null,
      unknownBackgroundMode: network == NetworkKind.unknown ? mode : null,
    );
    await _persistence.save(key, mode.name);
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

/// ホイール送信（SGR 1006）が実証済みかどうか。
///
/// Phase 0 実測（tool/tmux-sgr-baseline/ の B1/B2 PASS・tmux 3.7b / herdr 0.7.5）により
/// tmux / herdr 両 backend で SGR 素通しが検証済みのため true。
/// 将来 `PaneCapabilities.wheelSend`（lib/services/backend/domain/pane_writer.dart）が
/// false に戻る場合は、この値も同時に false へ戻すこと。
/// 設定画面はこの値で未検証フォールバック注記を出し分ける。
// inventory: SETTINGS-SCROLL-SEND-007
final wheelSendVerifiedProvider = Provider<bool>((ref) => true);
