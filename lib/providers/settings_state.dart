/// アプリ設定の不変状態モデル（enum + 41 フィールド値オブジェクト + copyWith）を定義する。
library;

/// アップロード時のファイル名衝突ポリシー（#41）。
/// - [prompt]: 既定。衝突時にモーダルで上書き/リネーム/キャンセルを確認
/// - [autoRename]: 確認なしで自動リネーム（generateUniqueName）
enum TransferConflictPolicy {
  prompt,
  autoRename;

  /// SharedPreferences 永続化値。
  String get persistedValue =>
      this == TransferConflictPolicy.autoRename ? 'autoRename' : 'prompt';

  /// 永続化値からの復元（不正値は既定の prompt にフォールバック）。
  static TransferConflictPolicy fromPersisted(String? value) {
    return value == 'autoRename'
        ? TransferConflictPolicy.autoRename
        : TransferConflictPolicy.prompt;
  }
}

/// アプリ設定
class AppSettings {
  final bool darkMode;
  final double fontSize;
  final String fontFamily;
  final bool requireBiometricAuth;
  final bool enableNotifications;
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

  /// CJK Mode: IME確定ごとに全文送信して入力欄をクリアする旧来
  /// （v0.7.0-pre4）のDirectInput挙動を使うか。
  /// iOSのCJK系IMEで発生する多重送信回避用（設定UIはiOSのみ表示）。
  final bool cjkMode;

  /// DirectInput: Enter送信後もソフトウェアキーボードを開いたままにするか。
  final bool keepKeyboardOnEnter;

  /// ターミナルカーソルの表示設定
  final bool showTerminalCursor;

  /// OSC 8 リンクを確認モーダルなしで直接開く。
  /// default false = 確認モーダルを表示（Issue #61・後方互換）。
  final bool openLinksDirectly;

  /// 実験的: Herdr接続でカーソル位置スナップショットを取得する
  /// （Phase 1ではフラグとUIのみ・動作はPhase 2/3で実装）
  // inventory: SETTINGS-HERDR-CARET-001
  final bool experimentalHerdrCaretPositionEnabled;

  /// ペインナビゲーション方向の反転
  final bool invertPaneNavigation;

  /// スクロール送信の送信方式: 'wheel'（マウスホイール SGR 1006）/ 'key'（PgUp/PgDn）
  // inventory: SETTINGS-SCROLL-SEND-001
  final String scrollSendInput;

  /// スクロール送信方向の反転（ON でドラッグ上 = 下スクロール送信）
  // inventory: SETTINGS-INVERT-SCROLL-001
  final bool invertScrollSendDirection;

  /// スクロール送信モード中にターミナル全体が画面に収まるようズームを一時縮小
  // inventory: SETTINGS-AUTO-FIT-ZOOM-001
  final bool autoFitZoomOnScrollSend;

  /// 表示言語: 'system'（端末に従う）/ 'ja' / 'en'
  final String language;

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

  // --- ファイル転送設定（#41） ---
  /// アップロード時のファイル名衝突ポリシー
  final TransferConflictPolicy uploadConflictPolicy;

  /// 同時アップロード並列数
  final int uploadConcurrency;

  /// アップロード書き込みチャンクサイズ（KB）
  final int uploadChunkKb;

  const AppSettings({
    this.darkMode = true,
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrains Mono',
    this.requireBiometricAuth = false,
    this.enableNotifications = true,
    this.keepScreenOn = true,
    this.screenOrientation = 'portrait',
    this.refreshRate = 'auto',
    this.scrollbackLines = 10000,
    this.minFontSize = 8.0,
    this.zoomFactor = 1.0,
    this.adjustMode = 'autoFit',
    this.directInputEnabled = false,
    this.cjkMode = false,
    this.keepKeyboardOnEnter = false,
    this.showTerminalCursor = true,
    this.openLinksDirectly = false,
    // inventory: SETTINGS-HERDR-CARET-002
    this.experimentalHerdrCaretPositionEnabled = false,
    this.invertPaneNavigation = false,
    // inventory: SETTINGS-SCROLL-SEND-002
    this.scrollSendInput = 'wheel',
    // inventory: SETTINGS-INVERT-SCROLL-002
    this.invertScrollSendDirection = false,
    // inventory: SETTINGS-AUTO-FIT-ZOOM-002
    this.autoFitZoomOnScrollSend = false,
    this.language = 'system',
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
    this.uploadConflictPolicy = TransferConflictPolicy.prompt,
    this.uploadConcurrency = 2,
    this.uploadChunkKb = 256,
  });

  bool get isAutoFit => adjustMode == 'autoFit';
  bool get isAutoResize => adjustMode == 'autoResize';

  AppSettings copyWith({
    bool? darkMode,
    double? fontSize,
    String? fontFamily,
    bool? requireBiometricAuth,
    bool? enableNotifications,
    bool? keepScreenOn,
    String? screenOrientation,
    String? refreshRate,
    int? scrollbackLines,
    double? minFontSize,
    double? zoomFactor,
    String? adjustMode,
    bool? directInputEnabled,
    bool? cjkMode,
    bool? keepKeyboardOnEnter,
    bool? showTerminalCursor,
    bool? openLinksDirectly,
    // inventory: SETTINGS-HERDR-CARET-003
    bool? experimentalHerdrCaretPositionEnabled,
    bool? invertPaneNavigation,
    // inventory: SETTINGS-SCROLL-SEND-003
    String? scrollSendInput,
    // inventory: SETTINGS-INVERT-SCROLL-003
    bool? invertScrollSendDirection,
    // inventory: SETTINGS-AUTO-FIT-ZOOM-003
    bool? autoFitZoomOnScrollSend,
    String? language,
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
    TransferConflictPolicy? uploadConflictPolicy,
    int? uploadConcurrency,
    int? uploadChunkKb,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      requireBiometricAuth: requireBiometricAuth ?? this.requireBiometricAuth,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      screenOrientation: screenOrientation ?? this.screenOrientation,
      refreshRate: refreshRate ?? this.refreshRate,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      minFontSize: minFontSize ?? this.minFontSize,
      zoomFactor: zoomFactor ?? this.zoomFactor,
      adjustMode: adjustMode ?? this.adjustMode,
      directInputEnabled: directInputEnabled ?? this.directInputEnabled,
      cjkMode: cjkMode ?? this.cjkMode,
      keepKeyboardOnEnter: keepKeyboardOnEnter ?? this.keepKeyboardOnEnter,
      showTerminalCursor: showTerminalCursor ?? this.showTerminalCursor,
      openLinksDirectly: openLinksDirectly ?? this.openLinksDirectly,
      // inventory: SETTINGS-HERDR-CARET-004
      experimentalHerdrCaretPositionEnabled:
          experimentalHerdrCaretPositionEnabled ??
          this.experimentalHerdrCaretPositionEnabled,
      invertPaneNavigation: invertPaneNavigation ?? this.invertPaneNavigation,
      scrollSendInput: scrollSendInput ?? this.scrollSendInput,
      invertScrollSendDirection:
          invertScrollSendDirection ?? this.invertScrollSendDirection,
      autoFitZoomOnScrollSend:
          autoFitZoomOnScrollSend ?? this.autoFitZoomOnScrollSend,
      language: language ?? this.language,
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
      uploadConflictPolicy: uploadConflictPolicy ?? this.uploadConflictPolicy,
      uploadConcurrency: uploadConcurrency ?? this.uploadConcurrency,
      uploadChunkKb: uploadChunkKb ?? this.uploadChunkKb,
    );
  }
}
