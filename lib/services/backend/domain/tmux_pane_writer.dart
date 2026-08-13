// inventory: TMUX-PANE-WRITER-000
/// tmux の [PaneWriter] 実装（既存 [TmuxContract] ラップ・後方互換）。
///
/// UI（`TerminalScreen`）から `tmuxFacade` + `tmuxExecutor` の直叩きを排除し、
/// バックエンド分岐を [PaneWriter] に構造的に集約する（R3: stale tmuxProvider
/// への誤送信の構造的対策）。各操作は既存の [TmuxContract] 呼び出しへ委譲する
/// ため、**tmux のコマンド文字列・既存テストは不変**（後方互換）。
///
/// Phase 1（T8）で UI が実際に経由する操作（sendText / sendKey / selectPane /
/// splitPane / closePane / pasteText + 絶対値 resize・bracketed paste）のみを
/// 委譲し、残りの interface メソッド（Phase 2 で配線する zoom / rename /
/// tab・workspace CRUD / 画像転送 等）は [UnsupportedPaneOperationException]
/// を投げる（Phase 0 の `_Phase0PaneWriter` と同じ失敗ポリシー・R4/R9）。
library;

import '../../tmux/tmux_command_builder.dart' show SplitDirection;
import '../../tmux/tmux_command_executor.dart';
import '../../tmux/tmux_contract.dart';
import 'pane_writer.dart';

// inventory: TMUX-PANE-WRITER-001
/// tmux の [PaneWriter] 実装。
class TmuxPaneWriter implements PaneWriter {
  /// [facade] は通常 [TmuxFacade]（グローバル `tmuxFacade`）。テストでは
  /// 記録用 fake を注入できる。 [executor] は接続中の SSH クライアントの
  /// [TmuxCommandExecutor]（`SshClient.tmuxExecutor`）。
  TmuxPaneWriter(this._facade, this._executor);

  final TmuxContract _facade;
  final TmuxCommandExecutor _executor;

  /// tmux は全操作能力を持つ。UI はこの能力（`_can` 判定）に従って操作を
  /// 有効化する。
  @override
  PaneCapabilities get capabilities => const PaneCapabilities(
        sendText: true,
        sendKeys: true,
        focus: true,
        split: true,
        close: true,
        rename: true,
        zoom: true,
        resize: true,
        paste: true,
        copyMode: true,
        imageTransfer: true,
        workspaceCrud: true,
        tabCrud: true,
        absoluteResize: true,
      );

  /// tmux は全キーを send-keys で送信できるため、同一キー名の send-keys 経路
  /// を返す（Q-07 の変換表は herdr 用・[PaneKeyMap]）。
  @override
  HerdrKeyRoute mapSpecialKey(String tmuxKey) => HerdrKeyRoute.sendKeys(tmuxKey);

  // ===== 委譲（Phase 1 で UI が経由する操作）=====

  /// テキストをリテラル送信（`send-keys -l`。従来の `_sendKeyData` 相当）。
  @override
  Future<void> sendText(String paneId, String text) =>
      _facade.sendKeysNoWait(_executor, paneId, text, literal: true);

  /// tmux キー名のまま特殊キー送信（`send-keys`。従来の `_sendSpecialKey`
  /// 相当）。tmux は全キーをそのまま送れるため `mapSpecialKey` の変換は
  /// 使わない。
  @override
  Future<void> sendKey(String paneId, String tmuxKey) =>
      _facade.sendKeysNoWait(_executor, paneId, tmuxKey, literal: false);

  /// pane を選択（`select-pane` + focus-in。従来の `_selectPane` 相当）。
  ///
  /// 注: 既存 UI は `previousPaneId` による focus-out（`\x1b[O`）も送っていた
  /// が、[PaneWriter] interface には previousPaneId が無いため省略する
  /// （後方互換の範囲で許容される最小の変更。select-pane / focus-in は維持）。
  @override
  Future<void> selectPane(String paneId) => _facade.selectPane(_executor, paneId);

  /// 分割（`split-window`）。[direction]: `'right'` → 水平（-h）・
  /// `'down'` → 垂直（-v）。[ratio] はパーセント（-p）へ換算。
  @override
  Future<void> splitPane(
    String paneId,
    String direction, {
    double? ratio,
    String? cwd,
  }) {
    final tmuxDirection = direction == 'right'
        ? SplitDirection.horizontal
        : SplitDirection.vertical;
    return _facade.splitPane(
      _executor,
      target: paneId,
      direction: tmuxDirection,
      startDirectory: cwd,
      percentage: ratio == null ? null : (ratio * 100).round(),
    );
  }

  /// pane を閉じる（`kill-pane`。破壊的 close の唯一経路・Q-03）。
  @override
  Future<void> closePane(String paneId) => _facade.killPane(_executor, paneId);

  /// 複数行貼り付け（`load-buffer` + `paste-buffer`。従来の
  /// `_sendMultilineText` 相当・bracketed paste 対応）。
  @override
  Future<void> pasteText(String paneId, String text) =>
      _facade.pasteText(_executor, target: paneId, text: text);

  // ===== tmux 固有（[PaneWriter] interface では表現できない操作）=====

  /// 絶対値 resize（cols/rows 指定・従来の `_handleResizePane` 相当）。
  ///
  /// [PaneWriter.resizePane] は相対分数（herdr・Q-04）のため、tmux の絶対値
  /// resize はこの tmux 固有メソッドへ委譲する。呼び出し側は
  /// `absoluteResize` capability（`_can`）でガードする。
  Future<void> resizePaneAbsolute(String paneId, {int? cols, int? rows}) =>
      _facade.resizePane(_executor, paneId, cols: cols, rows: rows);

  /// bracketed paste（画像パス注入の既存 tmux 経路・`_injectImagePath` 相当）。
  Future<void> sendBracketedPaste({
    required String paneId,
    required String path,
    bool autoEnter = false,
    bool bracketedPaste = true,
  }) =>
      _facade.sendBracketedPaste(
        _executor,
        paneId: paneId,
        path: path,
        autoEnter: autoEnter,
        bracketedPaste: bracketedPaste,
      );

  // ===== 未配線（Phase 2 で導入・現在の tmux UI は PaneNavigator / 既存
  // facade 直接経由のため、interface メソッドとして呼ばれない）=====

  @override
  Future<void> focusPaneDirection(String paneId, String direction) =>
      _unsupported('focusPaneDirection');

  @override
  Future<void> renamePane(String paneId, String label) =>
      _unsupported('renamePane');

  @override
  Future<void> zoomPane(String paneId, {String mode = 'toggle'}) =>
      _unsupported('zoomPane');

  @override
  Future<void> resizePane(String paneId, String direction, double amount) =>
      _unsupported('resizePane');

  @override
  Future<void> createTab(String workspaceId, {String? label, bool? focus}) =>
      _unsupported('createTab');

  @override
  Future<void> closeTab(String tabId) => _unsupported('closeTab');

  @override
  Future<void> renameTab(String tabId, String label) =>
      _unsupported('renameTab');

  @override
  Future<void> focusTab(String tabId) => _unsupported('focusTab');

  @override
  Future<void> createWorkspace(String label) => _unsupported('createWorkspace');

  @override
  Future<void> closeWorkspace(String workspaceId) =>
      _unsupported('closeWorkspace');

  @override
  Future<void> renameWorkspace(String workspaceId, String label) =>
      _unsupported('renameWorkspace');

  @override
  Future<void> focusWorkspace(String workspaceId) =>
      _unsupported('focusWorkspace');

  @override
  Future<void> imageTransfer(String path) => _unsupported('imageTransfer');

  Never _unsupported(String operation) => throw UnsupportedPaneOperationException(
        operation: operation,
        backend: 'tmux',
        message: 'この操作は tmux ではまだ配線されていません（Phase 2 で導入予定）',
      );
}
