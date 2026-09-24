/// view-input が session-runtime / herdr / root から受ける入力を抽象化する
/// 中立 interface 群。
///
/// view-input は具象（`_TerminalScreenState` / session-runtime の controller /
/// herdr の API）を import せず、すべてこの群と [TerminalViewportPort] 経由で
/// 相互作用する。実装は root State（= session-runtime の合成ルート）と herdr
/// 領域が提供する。
library;

import '../../../services/backend/domain/pane_frame_reader.dart' show PaneCaret;
import '../../../services/backend/domain/pane_writer.dart' show PaneWriter;
import '../../../services/tmux/pane_navigator.dart' show SwipeDirection;

/// ペイン送信の窓口（session-runtime が実装）。
///
/// `_paneWriter` / `_targetSource?.currentPaneId` / SSH 接続状態・
/// `_boostPolling` / `_recordHerdrSwitchEvent` / tmux copy-mode の直叩きを
/// 集約する。
abstract interface class TerminalPaneSendPort {
  /// 現在のペインへの書き込み（未接続・取得前は null）。
  PaneWriter? get paneWriter;

  /// 現在の表示対象 pane ID（`_TargetSource` 経由）。
  String? get currentPaneId;

  /// SSH 接続中か（未接続時のキュー/破棄判定）。
  bool get isConnected;

  /// 表示更新の高頻度化を一時的に促す（`_boostPolling`）。
  void boostPolling();

  /// 最小監視（A8 リングバッファ + debugPrint）。
  void recordHerdrSwitchEvent(String event);

  /// tmux copy-mode の対象（`tmuxProvider.notifier.currentTarget`。未接続時 null）。
  String? get currentTmuxTarget;

  /// tmux copy-mode へ入る（`tmuxFacade.enterCopyModeNoWait` + boost）。
  Future<void> enterCopyMode(String target);

  /// tmux copy-mode を終了する（`tmuxFacade.cancelCopyModeNoWait` + boost）。
  Future<void> exitCopyMode(String target);
}

/// キー送信・スワイプ・paste の能力判定（root/session-runtime が実装）。
///
/// HEAD の `_can(const PaneCapabilities(...))` の各ゲートに対応する。
abstract interface class TerminalInputCapabilities {
  bool get canSendText;
  bool get canSendSpecialKey;
  bool get canFocusDirection;
  bool get canCopyMode;
  bool get canPaste;
  bool get canWheelSend;
}

/// 表示内容（`_viewNotifier`）と履歴読み取り（session-runtime が実装）。
///
/// view-input は `_TerminalViewData` / `_paneReader` / `_frameReader` を直接
/// 触らず、この port 経由で読み書きする。
abstract interface class TerminalScrollbackPort {
  /// 履歴読み取りが可能か（SSH 接続 + reader 取得済み）。
  bool get canRead;

  /// 現在の表示コンテンツ（`_viewNotifier.value.content`）。
  String get displayedContent;

  /// 現在の表示 pane 幅（fit-zoom 用）。
  int get displayedPaneWidth;

  /// 現在の表示 pane 高さ（fit-zoom 用）。
  int get displayedPaneHeight;

  /// 現在の表示 caret（C1 の herdr caret 判定用）。
  PaneCaret? get displayedCaret;

  /// スクロールバック上限行数（`PaneHistoryPolicy` 解決済み値）。
  int get scrollbackLimit;

  /// 非同期 read 開始前の表示対象同一性を記録する。
  Object? captureTargetIdentity();

  /// スクロールバック全体を一括取得する（読み込めない場合 null）。
  Future<String?> readScrollbackContent();

  /// 表示コンテンツを差し替える（`_viewNotifier.value = copyWith(content:)`）。
  void setDisplayedContent(String content);
}

/// 表示対象の同一性照合（herdr API が実装・tmux は常に true を返す）。
abstract interface class TerminalTargetIdentityValidator {
  /// [identity]（`captureTargetIdentity` の戻り値）が現在の表示対象か。
  /// null（tmux パス・cache 未生成）は常に true。
  bool isCurrent(Object? identity);
}

/// pane ナビゲーション（2 本指スワイプ / navigableDirections・V5）。
///
/// tmux は session-runtime（`PaneNavigator` + `_selectPane`）が、herdr は
/// herdr 領域の navigation API が実装する。
abstract interface class TerminalNavigationPort {
  /// herdr backend か（`_backendKind == MultiplexerBackendKind.herdr`）。
  bool get isHerdr;

  /// tmux: 隣接 pane を解決して選択する。herdr: no-op（focusPaneDirection 使用）。
  Future<void> selectAdjacentPane(
    SwipeDirection direction, {
    required bool invert,
  });

  /// tmux: 隣接方向マップ。herdr: レイアウト矩形からの隣接判定。
  Map<SwipeDirection, bool>? navigableDirections({required bool invert});

  /// herdr: 方向フォーカス（`pane focus --direction`）。tmux は no-op。
  Future<void> focusPaneDirection(SwipeDirection direction);
}

/// root への副作用通知（context を協調オブジェクトに保持させないため callback 化）。
abstract interface class TerminalInputHost {
  /// State が mount 中か（`mounted`）。
  bool get isMounted;

  /// dispose 済みか（`_isDisposed`・P0 以降 true）。
  bool get isDisposed;

  /// `setState(() {})` 相当（モード遷移後の単一リビルド）。
  void markNeedsBuild();

  /// FAB（`_scrollToBottomKey.currentState?.show()`）を表示する。
  void showScrollToBottomButton();

  /// `termInputQueueFull` SnackBar を表示する（多重抑止なし・HEAD 同等）。
  void notifyInputQueueFull();

  /// `termMultilineNeedsConnection` SnackBar を表示する。
  void notifyMultilineNeedsConnection();

  /// herdr `invalid_key` の防御的 SnackBar（T19・R9・HEAD 同等）。
  void notifyHerdrInvalidKey();
}
