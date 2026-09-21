// inventory: HERDR-MUT-000
/// mutation 操作 17 個を提供する（sendText / sendKey / focusDirection /
/// edges / resize / zoom / rename / close / split / tab CRUD /
/// workspace CRUD）。
///
/// 本クライアントは**送信経路選択**（[HerdrCommandExecutor.trySendNoWait]
/// 成功 → 素の結果 / 失敗 → executor へ委譲）のみを行う。
/// 実行（CommandRequest 組立・例外分類）は [HerdrCommandExecutor.execMutation]、
/// 結果解析は [HerdrMutationResult.parse] へ委譲する。
library;

import 'herdr_command_executor.dart';
import 'herdr_commands.dart';
import 'herdr_mutation_result.dart';

/// mutation 操作のクライアント。
///
/// 実行と解析を executor / [HerdrMutationResult.parse] へ委譲し、
/// fire-and-forget 送信（[HerdrCommandExecutor.trySendNoWait]）が成功した
/// 場合のみ素の成功結果を返す分岐を維持する。
class HerdrMutationClient {
  final HerdrCommandExecutor _exec;

  HerdrMutationClient(this._exec);

  // inventory: HERDR-ADAPTER-021
  /// pane へテキストを送信する（Q-06）。
  ///
  /// fire-and-forget 化（バグ2: 描画遅延の修正）: 入力専用の持続的シェル
  /// （[BackendAdapter.inputTransport]）が利用可能なら [sendNoWait] で即時送信
  /// し、exec ロック直列化・チャネル開閉を回避する（tmux の
  /// `sendKeysNoWait` → `inputTransport.sendNoWait` と対称）。入力シェルが
  /// 無い・送信失敗時は従来どおり
  /// [HerdrCommandExecutor.execMutation]（exec チャネル・応答待ち）に
  /// フォールバックする。
  Future<HerdrMutationResult> sendText(
    String paneId,
    String text, {
    Duration? timeout,
  }) {
    final command = HerdrCommands.paneSendText(paneId, text);
    if (_exec.trySendNoWait(command)) {
      return Future.value(const HerdrMutationResult());
    }
    return _exec
        .execMutation(command, timeout: timeout)
        .then(HerdrMutationResult.parse);
  }

  // inventory: HERDR-ADAPTER-022
  /// pane へキーを送信する（Q-07）。
  ///
  /// [keyName] は `PaneKeyMap.mapSpecialKey` で変換済みの herdr キー名を想定
  /// （受理キーはそのまま・拒否キーは `send-text` 経路へは [sendText] を使う）。
  /// [sendText] と同様に fire-and-forget 化（入力シェルがあれば [sendNoWait]）。
  Future<HerdrMutationResult> sendKey(
    String paneId,
    String keyName, {
    Duration? timeout,
  }) {
    final command = HerdrCommands.paneSendKeys(paneId, keyName);
    if (_exec.trySendNoWait(command)) {
      return Future.value(const HerdrMutationResult());
    }
    return _exec
        .execMutation(command, timeout: timeout)
        .then(HerdrMutationResult.parse);
  }

  // inventory: HERDR-ADAPTER-023
  /// 方向 focus（`--pane` 指定）。
  ///
  /// 隣接なしは `changed:false` + `reason:"no_neighbor"` の soft 失敗
  /// （[HerdrMutationResult.isNoNeighbor]）。応答 layout で同期する。
  Future<HerdrMutationResult> focusDirection(
    String paneId,
    String direction, {
    Duration? timeout,
  }) => _exec
      .execMutation(
        HerdrCommands.paneFocus(paneId, direction),
        timeout: timeout,
      )
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-024
  /// 隣接方向の有無を返す（navigableDirections 表示に直結）。
  Future<HerdrMutationResult> edges(String paneId, {Duration? timeout}) => _exec
      .execMutation(HerdrCommands.paneEdges(paneId), timeout: timeout)
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-025
  /// 相対分数 resize（Q-04）。
  ///
  /// [amount] は現在 ratio への加算・[0.1, 0.9] クランプ。分割境界外は
  /// `changed:false` + `reason:"unchanged"`（[HerdrMutationResult.isUnchanged]）。
  Future<HerdrMutationResult> resizePane(
    String paneId,
    String direction,
    double amount, {
    Duration? timeout,
  }) => _exec
      .execMutation(
        HerdrCommands.paneResize(paneId, direction, amount),
        timeout: timeout,
      )
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-026
  /// zoom（Q-02）。
  ///
  /// [mode]: `'toggle'` / `'on'` / `'off'`（既定 `'toggle'`）。
  Future<HerdrMutationResult> zoomPane(
    String paneId, {
    String mode = 'toggle',
    Duration? timeout,
  }) => _exec
      .execMutation(
        HerdrCommands.paneZoom(paneId, mode: mode),
        timeout: timeout,
      )
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-027
  /// ラベル変更（Q-02）。
  Future<HerdrMutationResult> renamePane(
    String paneId,
    String label, {
    Duration? timeout,
  }) => _exec
      .execMutation(HerdrCommands.paneRename(paneId, label), timeout: timeout)
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-028
  /// pane を閉じる（**破壊的 close の唯一経路**・Q-03）。
  ///
  /// 対象不在は `pane_not_found` → [HerdrTargetNotFoundException]
  /// （`isHerdrTargetNotFound` で分類・再解決へ）。
  Future<HerdrMutationResult> closePane(String paneId, {Duration? timeout}) =>
      _exec
          .execMutation(HerdrCommands.paneClose(paneId), timeout: timeout)
          .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-029
  /// pane を分割する（Q-02）。
  ///
  /// 応答は layout を含まないため、反映は別途 `snapshot()` で同期する
  /// （T0 実測 6-a・H5 単一経路）。
  Future<HerdrMutationResult> splitPane(
    String paneId,
    String direction, {
    double? ratio,
    String? cwd,
    Duration? timeout,
  }) => _exec
      .execMutation(
        HerdrCommands.paneSplit(paneId, direction, ratio: ratio, cwd: cwd),
        timeout: timeout,
      )
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-032
  /// tab を作成する（Q-05）。
  ///
  /// [workspaceId]: 作成先の workspace ID（例: "w1"）。
  /// [label]: 表示ラベル（省略可）。
  /// [cwd]: ルート pane の開始ディレクトリ（省略可）。
  /// [focus]: null なら省略（herdr 既定: フォーカス不変）・true で `--focus`・
  /// false で `--no-focus`。
  /// 応答は layout を含まない（`result.tab`）ため、反映は別途 `snapshot()`
  /// で同期する（T18 単一経路）。対象不在は `workspace_not_found` →
  /// [HerdrTargetNotFoundException]。
  Future<HerdrMutationResult> tabCreate(
    String workspaceId, {
    String? label,
    String? cwd,
    bool? focus,
    Duration? timeout,
  }) => _exec
      .execMutation(
        HerdrCommands.tabCreate(
          workspaceId,
          label: label,
          cwd: cwd,
          focus: focus,
        ),
        timeout: timeout,
      )
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-033
  /// tab を閉じる（Q-05）。
  ///
  /// workspace の最後の tab を閉じると workspace も連鎖終了する。
  /// 対象不在は `tab_not_found` → [HerdrTargetNotFoundException]。
  Future<HerdrMutationResult> tabClose(String tabId, {Duration? timeout}) =>
      _exec
          .execMutation(HerdrCommands.tabClose(tabId), timeout: timeout)
          .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-034
  /// tab のラベルを変更する（Q-05）。
  Future<HerdrMutationResult> tabRename(
    String tabId,
    String label, {
    Duration? timeout,
  }) => _exec
      .execMutation(HerdrCommands.tabRename(tabId, label), timeout: timeout)
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-035
  /// tab へフォーカスする（Q-05）。
  Future<HerdrMutationResult> tabFocus(String tabId, {Duration? timeout}) =>
      _exec
          .execMutation(HerdrCommands.tabFocus(tabId), timeout: timeout)
          .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-036
  /// workspace を作成する（Q-05）。
  ///
  /// workspace 作成と同時に最初の tab と root pane も作られる。応答は layout
  /// を含まない（`result.workspace`）ため、反映は別途 `snapshot()` で同期する
  /// （T18 単一経路）。
  /// [label]: 表示ラベル（省略可）。[cwd]: ルート pane の開始ディレクトリ。
  /// [focus]: null なら省略（herdr 既定: フォーカス不変）・true で `--focus`・
  /// false で `--no-focus`。
  Future<HerdrMutationResult> workspaceCreate({
    String? label,
    String? cwd,
    bool? focus,
    Duration? timeout,
  }) => _exec
      .execMutation(
        HerdrCommands.workspaceCreate(label: label, cwd: cwd, focus: focus),
        timeout: timeout,
      )
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-037
  /// workspace を閉じる（Q-05）。
  ///
  /// 対象不在は `workspace_not_found` → [HerdrTargetNotFoundException]。
  Future<HerdrMutationResult> workspaceClose(
    String workspaceId, {
    Duration? timeout,
  }) => _exec
      .execMutation(HerdrCommands.workspaceClose(workspaceId), timeout: timeout)
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-038
  /// workspace のラベルを変更する（Q-05）。
  Future<HerdrMutationResult> workspaceRename(
    String workspaceId,
    String label, {
    Duration? timeout,
  }) => _exec
      .execMutation(
        HerdrCommands.workspaceRename(workspaceId, label),
        timeout: timeout,
      )
      .then(HerdrMutationResult.parse);

  // inventory: HERDR-ADAPTER-039
  /// workspace へフォーカスする（Q-05）。
  Future<HerdrMutationResult> workspaceFocus(
    String workspaceId, {
    Duration? timeout,
  }) => _exec
      .execMutation(HerdrCommands.workspaceFocus(workspaceId), timeout: timeout)
      .then(HerdrMutationResult.parse);
}
