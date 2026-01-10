import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// アプリケーション設定
@freezed
class AppSettings with _$AppSettings {
  const AppSettings._();

  const factory AppSettings({
    /// 表示設定
    @Default(DisplaySettings()) DisplaySettings display,

    /// ターミナル設定
    @Default(TerminalSettings()) TerminalSettings terminal,

    /// SSH設定
    @Default(SshSettings()) SshSettings ssh,

    /// セキュリティ設定
    @Default(SecuritySettings()) SecuritySettings security,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}

/// 表示設定
@freezed
class DisplaySettings with _$DisplaySettings {
  const DisplaySettings._();

  const factory DisplaySettings({
    /// ダークモード
    @Default(true) bool darkMode,

    /// システムテーマに従う
    @Default(true) bool useSystemTheme,

    /// 画面の向き固定
    @Default(false) bool lockOrientation,

    /// 画面常時点灯
    @Default(true) bool keepScreenOn,

    /// フルスクリーンモード
    @Default(false) bool fullScreen,

    /// ステータスバー表示
    @Default(true) bool showStatusBar,
  }) = _DisplaySettings;

  factory DisplaySettings.fromJson(Map<String, dynamic> json) =>
      _$DisplaySettingsFromJson(json);
}

/// ターミナル設定
@freezed
class TerminalSettings with _$TerminalSettings {
  const TerminalSettings._();

  const factory TerminalSettings({
    /// フォントファミリー
    @Default(FontFamily.jetBrainsMono) FontFamily fontFamily,

    /// フォントサイズ
    @Default(14.0) double fontSize,

    /// 行間
    @Default(1.2) double lineHeight,

    /// カラーテーマ
    @Default(ColorTheme.dracula) ColorTheme colorTheme,

    /// カーソルブリンク
    @Default(true) bool cursorBlink,

    /// カーソルスタイル（block, underline, bar）
    @Default('block') String cursorStyle,

    /// スクロールバック行数
    @Default(10000) int scrollbackLines,

    /// ベル音
    @Default(true) bool bellSound,

    /// ベル振動
    @Default(true) bool bellVibrate,

    /// 特殊キーバー表示
    @Default(true) bool showSpecialKeysBar,

    /// コピー時に自動選択解除
    @Default(true) bool autoClearSelection,

    /// ダブルタップで単語選択
    @Default(true) bool doubleTapSelectWord,

    /// トリプルタップで行選択
    @Default(true) bool tripleTapSelectLine,

    /// 長押しでコンテキストメニュー
    @Default(true) bool longPressContextMenu,

    /// ピンチでズーム
    @Default(true) bool pinchToZoom,

    /// 最小フォントサイズ
    @Default(8.0) double minFontSize,

    /// 最大フォントサイズ
    @Default(32.0) double maxFontSize,
  }) = _TerminalSettings;

  factory TerminalSettings.fromJson(Map<String, dynamic> json) =>
      _$TerminalSettingsFromJson(json);

  /// フォントファミリー名を取得
  String get fontFamilyName => switch (fontFamily) {
        FontFamily.jetBrainsMono => 'JetBrains Mono',
        FontFamily.firaCode => 'Fira Code',
        FontFamily.meslo => 'Meslo',
        FontFamily.hackGen => 'HackGen',
        FontFamily.plemolJP => 'PlemolJP',
      };
}

/// SSH設定
@freezed
class SshSettings with _$SshSettings {
  const SshSettings._();

  const factory SshSettings({
    /// 接続タイムアウト（秒）
    @Default(30) int connectionTimeout,

    /// キープアライブ間隔（秒）
    @Default(60) int keepAliveInterval,

    /// 再接続試行回数
    @Default(3) int reconnectAttempts,

    /// 再接続待機時間（秒）
    @Default(5) int reconnectDelay,

    /// 圧縮有効
    @Default(false) bool compression,

    /// デフォルトのPTY幅
    @Default(80) int defaultPtyWidth,

    /// デフォルトのPTY高さ
    @Default(24) int defaultPtyHeight,

    /// デフォルトのTERM
    @Default('xterm-256color') String defaultTerm,
  }) = _SshSettings;

  factory SshSettings.fromJson(Map<String, dynamic> json) =>
      _$SshSettingsFromJson(json);
}

/// セキュリティ設定
@freezed
class SecuritySettings with _$SecuritySettings {
  const SecuritySettings._();

  const factory SecuritySettings({
    /// 生体認証でロック解除
    @Default(false) bool biometricUnlock,

    /// アプリ起動時に認証を要求
    @Default(false) bool requireAuthOnLaunch,

    /// バックグラウンド時に認証を要求
    @Default(false) bool requireAuthOnResume,

    /// 認証タイムアウト（秒）
    @Default(300) int authTimeout,

    /// クリップボード自動クリア（秒、0で無効）
    @Default(60) int clipboardClearTimeout,

    /// 画面キャプチャを許可
    @Default(true) bool allowScreenCapture,

    /// パスワード表示を許可
    @Default(false) bool allowShowPassword,

    /// 秘密鍵表示を許可
    @Default(false) bool allowShowPrivateKey,
  }) = _SecuritySettings;

  factory SecuritySettings.fromJson(Map<String, dynamic> json) =>
      _$SecuritySettingsFromJson(json);
}
