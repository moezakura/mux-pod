// inventory: HERDR-ADAPTER-000
/// SSH 経由で herdr CLI を実行する adapter（公開ファサード）。
///
/// 責務別部品を合成し、従来の全公開 API（isConnected + read 4 + mutation 17）
/// を委譲する。
/// - [HerdrCommandExecutor]: exec 基盤（read / mutation 共通・エラー分類）
/// - [HerdrReadClient]: read 操作（preflight / status / snapshot / paneRead）
/// - [HerdrMutationClient]: mutation 操作 17 個（実行は executor・解析は
///   [HerdrMutationResult.parse] へ委譲）
///
/// 通常の継承可能クラスのまま保ち、テストが `snapshot()` を override して
/// 差し替えできるようにする（herdr_snapshot_cache_test / caret テスト）。
library;

import '../../l10n/app_localizations.dart';
import '../backend/backend_adapter.dart';
import 'herdr_command_executor.dart';
import 'herdr_models.dart';
import 'herdr_mutation_client.dart';
import 'herdr_mutation_result.dart';
import 'herdr_read_client.dart';

/// herdr CLI へのアクセスを提供する adapter（公開ファサード）。
///
/// 既存の [BackendAdapter] をラップし、CLI 先行方式で herdr の JSON 返却
/// コマンドを実行・パースする。read 側（snapshot / pane read）に加え、
/// mutation 実行基盤（[HerdrMutationResult]）と mutation メソッド群
/// （sendText / sendKey / focusDirection / edges / resize / zoom / rename /
/// close / split / tab CRUD / workspace CRUD）を提供する。mutation は公開済み
/// （G6 合意#3 改訂・Q-01: 全 mutation 解禁の 1 回リリース）。
///
/// 実装は責務別部品（[HerdrCommandExecutor] / [HerdrReadClient] /
/// [HerdrMutationClient]）へ委譲する。公開 API とシグネチャは移行前と
/// 完全互換（継承可能な通常クラス）。
class HerdrAdapter {
  late final HerdrCommandExecutor _executor;
  late final HerdrReadClient _read;
  late final HerdrMutationClient _mutation;

  HerdrAdapter(
    BackendAdapter backend, {
    String? userExecutablePath,
    AppLocalizations? l10n,
  }) {
    _executor = HerdrCommandExecutor(
      backend,
      userExecutablePath: userExecutablePath,
      l10n: l10n,
    );
    _read = HerdrReadClient(_executor);
    _mutation = HerdrMutationClient(_executor);
  }

  /// 接続中かどうか（[HerdrCommandExecutor] へ委譲）。
  bool get isConnected => _executor.isConnected;

  // inventory: HERDR-ADAPTER-002
  /// preflight: `herdr status --json` を実行し protocol（最小 17）を検証する。
  ///
  /// 実装は [HerdrReadClient.preflight] へ委譲（詳細はそちらを参照）。
  /// server 未稼働の場合は [HerdrServerNotRunningException]、
  /// protocol が 17 未満の場合は [HerdrProtocolMismatchException] を投げる。
  Future<HerdrStatus> preflight({Duration? timeout}) =>
      _read.preflight(timeout: timeout);

  // inventory: HERDR-ADAPTER-034
  /// `herdr status --json` の生結果を返す（protocol 検証なし）。
  ///
  /// 実装は [HerdrReadClient.status] へ委譲（詳細はそちらを参照）。
  Future<HerdrStatus> status({Duration? timeout}) =>
      _read.status(timeout: timeout);

  // inventory: HERDR-ADAPTER-003
  /// 全階層スナップショット（workspace/tab/pane）を取得する。
  ///
  /// 実装は [HerdrReadClient.snapshot] へ委譲。テストはこのメソッドを
  /// override して差し替える。
  Future<HerdrSnapshot> snapshot({Duration? timeout}) =>
      _read.snapshot(timeout: timeout);

  // inventory: HERDR-ADAPTER-004
  /// pane の内容を読み取る。
  ///
  /// 実装は [HerdrReadClient.paneRead] へ委譲（詳細はそちらを参照）。
  /// [viaPersistent] は持続的シェル経由で実行する（デフォルト false）。
  Future<HerdrPaneContent> paneRead(
    String paneId, {
    String source = 'recent',
    int? lines,
    bool ansi = false,
    bool viaPersistent = false,
    Duration? timeout,
  }) => _read.paneRead(
    paneId,
    source: source,
    lines: lines,
    ansi: ansi,
    viaPersistent: viaPersistent,
    timeout: timeout,
  );

  // ===== mutation（Q-02/Q-03/Q-06/Q-07。公開済み）=====
  // 実装は [HerdrMutationClient] へ委譲（送信経路選択のみが実ロジック。
  // 実行は executor・解析は [HerdrMutationResult.parse]）。

  // inventory: HERDR-ADAPTER-021
  /// pane へテキストを送信する（Q-06）。fire-and-forget 化（バグ2）。
  ///
  /// 実装は [HerdrMutationClient.sendText] へ委譲（詳細はそちらを参照）。
  Future<HerdrMutationResult> sendText(
    String paneId,
    String text, {
    Duration? timeout,
  }) => _mutation.sendText(paneId, text, timeout: timeout);

  // inventory: HERDR-ADAPTER-022
  /// pane へキーを送信する（Q-07）。[sendText] と同様に fire-and-forget 化。
  ///
  /// 実装は [HerdrMutationClient.sendKey] へ委譲（詳細はそちらを参照）。
  Future<HerdrMutationResult> sendKey(
    String paneId,
    String keyName, {
    Duration? timeout,
  }) => _mutation.sendKey(paneId, keyName, timeout: timeout);

  // inventory: HERDR-ADAPTER-023
  /// 方向 focus（`--pane` 指定）。隣接なしは `changed:false` +
  /// `reason:"no_neighbor"` の soft 失敗（[HerdrMutationResult.isNoNeighbor]）。
  ///
  /// 実装は [HerdrMutationClient.focusDirection] へ委譲。
  Future<HerdrMutationResult> focusDirection(
    String paneId,
    String direction, {
    Duration? timeout,
  }) => _mutation.focusDirection(paneId, direction, timeout: timeout);

  // inventory: HERDR-ADAPTER-024
  /// 隣接方向の有無を返す（navigableDirections 表示に直結）。
  ///
  /// 実装は [HerdrMutationClient.edges] へ委譲。
  Future<HerdrMutationResult> edges(String paneId, {Duration? timeout}) =>
      _mutation.edges(paneId, timeout: timeout);

  // inventory: HERDR-ADAPTER-025
  /// 相対分数 resize（Q-04）。分割境界外は `changed:false` +
  /// `reason:"unchanged"`（[HerdrMutationResult.isUnchanged]）。
  ///
  /// 実装は [HerdrMutationClient.resizePane] へ委譲。
  Future<HerdrMutationResult> resizePane(
    String paneId,
    String direction,
    double amount, {
    Duration? timeout,
  }) => _mutation.resizePane(paneId, direction, amount, timeout: timeout);

  // inventory: HERDR-ADAPTER-026
  /// zoom（Q-02）。[mode]: `'toggle'` / `'on'` / `'off'`（既定 `'toggle'`）。
  ///
  /// 実装は [HerdrMutationClient.zoomPane] へ委譲。
  Future<HerdrMutationResult> zoomPane(
    String paneId, {
    String mode = 'toggle',
    Duration? timeout,
  }) => _mutation.zoomPane(paneId, mode: mode, timeout: timeout);

  // inventory: HERDR-ADAPTER-027
  /// ラベル変更（Q-02）。実装は [HerdrMutationClient.renamePane] へ委譲。
  Future<HerdrMutationResult> renamePane(
    String paneId,
    String label, {
    Duration? timeout,
  }) => _mutation.renamePane(paneId, label, timeout: timeout);

  // inventory: HERDR-ADAPTER-028
  /// pane を閉じる（**破壊的 close の唯一経路**・Q-03）。
  ///
  /// 対象不在は `pane_not_found` → [HerdrTargetNotFoundException]
  /// （`isHerdrTargetNotFound` で分類・再解決へ）。実装は
  /// [HerdrMutationClient.closePane] へ委譲。
  Future<HerdrMutationResult> closePane(String paneId, {Duration? timeout}) =>
      _mutation.closePane(paneId, timeout: timeout);

  // inventory: HERDR-ADAPTER-029
  /// pane を分割する（Q-02）。応答は layout を含まないため、反映は別途
  /// `snapshot()` で同期する（T0 実測 6-a・H5 単一経路）。
  ///
  /// 実装は [HerdrMutationClient.splitPane] へ委譲。
  Future<HerdrMutationResult> splitPane(
    String paneId,
    String direction, {
    double? ratio,
    String? cwd,
    Duration? timeout,
  }) => _mutation.splitPane(
    paneId,
    direction,
    ratio: ratio,
    cwd: cwd,
    timeout: timeout,
  );

  // inventory: HERDR-ADAPTER-032
  /// tab を作成する（Q-05）。応答は layout を含まない（`result.tab`）ため、
  /// 反映は別途 `snapshot()` で同期する（T18 単一経路）。
  ///
  /// 対象不在は `workspace_not_found` → [HerdrTargetNotFoundException]。
  /// 実装は [HerdrMutationClient.tabCreate] へ委譲。
  Future<HerdrMutationResult> tabCreate(
    String workspaceId, {
    String? label,
    String? cwd,
    bool? focus,
    Duration? timeout,
  }) => _mutation.tabCreate(
    workspaceId,
    label: label,
    cwd: cwd,
    focus: focus,
    timeout: timeout,
  );

  // inventory: HERDR-ADAPTER-033
  /// tab を閉じる（Q-05）。workspace の最後の tab を閉じると workspace も
  /// 連鎖終了する。対象不在は `tab_not_found` →
  /// [HerdrTargetNotFoundException]。実装は [HerdrMutationClient.tabClose]
  /// へ委譲。
  Future<HerdrMutationResult> tabClose(String tabId, {Duration? timeout}) =>
      _mutation.tabClose(tabId, timeout: timeout);

  // inventory: HERDR-ADAPTER-034
  /// tab のラベルを変更する（Q-05）。実装は [HerdrMutationClient.tabRename]
  /// へ委譲。
  Future<HerdrMutationResult> tabRename(
    String tabId,
    String label, {
    Duration? timeout,
  }) => _mutation.tabRename(tabId, label, timeout: timeout);

  // inventory: HERDR-ADAPTER-035
  /// tab へフォーカスする（Q-05）。実装は [HerdrMutationClient.tabFocus]
  /// へ委譲。
  Future<HerdrMutationResult> tabFocus(String tabId, {Duration? timeout}) =>
      _mutation.tabFocus(tabId, timeout: timeout);

  // inventory: HERDR-ADAPTER-036
  /// workspace を作成する（Q-05）。workspace 作成と同時に最初の tab と root
  /// pane も作られる。応答は layout を含まない（`result.workspace`）ため、
  /// 反映は別途 `snapshot()` で同期する（T18 単一経路）。
  ///
  /// 実装は [HerdrMutationClient.workspaceCreate] へ委譲。
  Future<HerdrMutationResult> workspaceCreate({
    String? label,
    String? cwd,
    bool? focus,
    Duration? timeout,
  }) => _mutation.workspaceCreate(
    label: label,
    cwd: cwd,
    focus: focus,
    timeout: timeout,
  );

  // inventory: HERDR-ADAPTER-037
  /// workspace を閉じる（Q-05）。対象不在は `workspace_not_found` →
  /// [HerdrTargetNotFoundException]。実装は
  /// [HerdrMutationClient.workspaceClose] へ委譲。
  Future<HerdrMutationResult> workspaceClose(
    String workspaceId, {
    Duration? timeout,
  }) => _mutation.workspaceClose(workspaceId, timeout: timeout);

  // inventory: HERDR-ADAPTER-038
  /// workspace のラベルを変更する（Q-05）。実装は
  /// [HerdrMutationClient.workspaceRename] へ委譲。
  Future<HerdrMutationResult> workspaceRename(
    String workspaceId,
    String label, {
    Duration? timeout,
  }) => _mutation.workspaceRename(workspaceId, label, timeout: timeout);

  // inventory: HERDR-ADAPTER-039
  /// workspace へフォーカスする（Q-05）。実装は
  /// [HerdrMutationClient.workspaceFocus] へ委譲。
  Future<HerdrMutationResult> workspaceFocus(
    String workspaceId, {
    Duration? timeout,
  }) => _mutation.workspaceFocus(workspaceId, timeout: timeout);
}
