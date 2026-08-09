// inventory: HERDR-ADAPTER-000
/// SSH 経由で herdr CLI を実行する adapter。
///
/// 既存の [BackendAdapter] をラップし、CLI 先行方式で herdr の JSON 返却
/// コマンドを実行・パースする。read 側（snapshot / pane read）に加え、
/// mutation 実行基盤（[_execMutation] / [HerdrMutationResult]）と mutation
/// メソッド群（sendText / sendKey / focusDirection / edges / resize /
/// zoom / rename / close / split / tab CRUD / workspace CRUD）を提供する。
/// mutation は公開済み（G6 合意#3 改訂: herdr read-only → 全 mutation
/// 解禁・Q-01 の 1 回リリース）。
library;

import 'dart:convert';

import '../backend/backend_adapter.dart';
import '../connection_error.dart';
import 'herdr_commands.dart';
import 'herdr_errors.dart';
import 'herdr_models.dart';
import 'herdr_parser.dart';

// inventory: HERDR-ADAPTER-001
/// herdr CLI へのアクセスを提供する adapter。
class HerdrAdapter {
  final BackendAdapter _backend;
  final String? _userExecutablePath;

  HerdrAdapter(
    this._backend, {
    String? userExecutablePath,
  }) : _userExecutablePath = userExecutablePath ?? _backend.userExecutablePath;

  /// 接続中かどうか。
  bool get isConnected => _backend.isConnected;

  // inventory: HERDR-ADAPTER-002
  /// preflight: `herdr status --json` を実行し protocol 17 を検証する。
  ///
  /// server 未稼働の場合は [HerdrServerNotRunningException]、
  /// protocol が 17 以外の場合は [HerdrProtocolMismatchException] を投げる。
  Future<HerdrStatus> preflight({Duration? timeout}) async {
    final stdout =
        await _execChecked(HerdrCommands.preflightCommand(), timeout: timeout);
    final HerdrStatus status;
    try {
      status = HerdrStatusParser.parse(stdout);
    } on FormatException catch (e) {
      throw HerdrCommandException(
        'Failed to parse herdr status output: ${e.message}',
      );
    }
    return HerdrPreflight.validate(status);
  }

  // inventory: HERDR-ADAPTER-003
  /// 全階層スナップショット（workspace/tab/pane）を取得する。
  Future<HerdrSnapshot> snapshot({Duration? timeout}) async {
    final stdout =
        await _execChecked(HerdrCommands.snapshot(), timeout: timeout);
    try {
      return HerdrSnapshotParser.parse(stdout);
    } on FormatException catch (e) {
      throw HerdrCommandException(
        'Failed to parse herdr snapshot output: ${e.message}',
      );
    }
  }

  // inventory: HERDR-ADAPTER-004
  /// pane の内容を読み取る。
  ///
  /// [source]: `'visible'`（可視領域）または `'recent'`（履歴含む）。
  /// [lines]: 読み取る行数（null なら全量）。
  /// [ansi]: true なら `--raw` で ANSI エスケープ付きの出力を取得する。
  Future<HerdrPaneContent> paneRead(
    String paneId, {
    String source = 'recent',
    int? lines,
    bool ansi = false,
    Duration? timeout,
  }) async {
    final stdout = await _execChecked(
      HerdrCommands.paneRead(paneId, source: source, lines: lines, ansi: ansi),
      timeout: timeout,
    );
    return HerdrPaneContentParser.parse(stdout, ansi: ansi);
  }

  // ===== mutation（Q-02/Q-03/Q-06/Q-07。公開済み）=====

  // inventory: HERDR-ADAPTER-021
  /// pane へテキストを送信する（Q-06）。
  Future<HerdrMutationResult> sendText(
    String paneId,
    String text, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.paneSendText(paneId, text), timeout: timeout);

  // inventory: HERDR-ADAPTER-022
  /// pane へキーを送信する（Q-07）。
  ///
  /// [keyName] は `PaneKeyMap.mapSpecialKey` で変換済みの herdr キー名を想定
  /// （受理キーはそのまま・拒否キーは `send-text` 経路へは [sendText] を使う）。
  Future<HerdrMutationResult> sendKey(
    String paneId,
    String keyName, {
    Duration? timeout,
  }) =>
      _execMutation(
        HerdrCommands.paneSendKeys(paneId, keyName),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-023
  /// 方向 focus（`--pane` 指定）。
  ///
  /// 隣接なしは `changed:false` + `reason:"no_neighbor"` の soft 失敗
  /// （[HerdrMutationResult.isNoNeighbor]）。応答 layout で同期する。
  Future<HerdrMutationResult> focusDirection(
    String paneId,
    String direction, {
    Duration? timeout,
  }) =>
      _execMutation(
        HerdrCommands.paneFocus(paneId, direction),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-024
  /// 隣接方向の有無を返す（navigableDirections 表示に直結）。
  Future<HerdrMutationResult> edges(
    String paneId, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.paneEdges(paneId), timeout: timeout);

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
  }) =>
      _execMutation(
        HerdrCommands.paneResize(paneId, direction, amount),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-026
  /// zoom（Q-02）。
  ///
  /// [mode]: `'toggle'` / `'on'` / `'off'`（既定 `'toggle'`）。
  Future<HerdrMutationResult> zoomPane(
    String paneId, {
    String mode = 'toggle',
    Duration? timeout,
  }) =>
      _execMutation(
        HerdrCommands.paneZoom(paneId, mode: mode),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-027
  /// ラベル変更（Q-02）。
  Future<HerdrMutationResult> renamePane(
    String paneId,
    String label, {
    Duration? timeout,
  }) =>
      _execMutation(
        HerdrCommands.paneRename(paneId, label),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-028
  /// pane を閉じる（**破壊的 close の唯一経路**・Q-03）。
  ///
  /// 対象不在は `pane_not_found` → [HerdrTargetNotFoundException]
  /// （`isHerdrTargetNotFound` で分類・再解決へ）。
  Future<HerdrMutationResult> closePane(
    String paneId, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.paneClose(paneId), timeout: timeout);

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
  }) =>
      _execMutation(
        HerdrCommands.paneSplit(paneId, direction, ratio: ratio, cwd: cwd),
        timeout: timeout,
      );

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
  }) =>
      _execMutation(
        HerdrCommands.tabCreate(workspaceId, label: label, cwd: cwd, focus: focus),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-033
  /// tab を閉じる（Q-05）。
  ///
  /// workspace の最後の tab を閉じると workspace も連鎖終了する。
  /// 対象不在は `tab_not_found` → [HerdrTargetNotFoundException]。
  Future<HerdrMutationResult> tabClose(
    String tabId, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.tabClose(tabId), timeout: timeout);

  // inventory: HERDR-ADAPTER-034
  /// tab のラベルを変更する（Q-05）。
  Future<HerdrMutationResult> tabRename(
    String tabId,
    String label, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.tabRename(tabId, label), timeout: timeout);

  // inventory: HERDR-ADAPTER-035
  /// tab へフォーカスする（Q-05）。
  Future<HerdrMutationResult> tabFocus(
    String tabId, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.tabFocus(tabId), timeout: timeout);

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
  }) =>
      _execMutation(
        HerdrCommands.workspaceCreate(label: label, cwd: cwd, focus: focus),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-037
  /// workspace を閉じる（Q-05）。
  ///
  /// 対象不在は `workspace_not_found` → [HerdrTargetNotFoundException]。
  Future<HerdrMutationResult> workspaceClose(
    String workspaceId, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.workspaceClose(workspaceId), timeout: timeout);

  // inventory: HERDR-ADAPTER-038
  /// workspace のラベルを変更する（Q-05）。
  Future<HerdrMutationResult> workspaceRename(
    String workspaceId,
    String label, {
    Duration? timeout,
  }) =>
      _execMutation(
        HerdrCommands.workspaceRename(workspaceId, label),
        timeout: timeout,
      );

  // inventory: HERDR-ADAPTER-039
  /// workspace へフォーカスする（Q-05）。
  Future<HerdrMutationResult> workspaceFocus(
    String workspaceId, {
    Duration? timeout,
  }) =>
      _execMutation(HerdrCommands.workspaceFocus(workspaceId), timeout: timeout);

  // inventory: HERDR-ADAPTER-030
  /// mutation コマンドを実行し [HerdrMutationResult] を返す。
  ///
  /// - **成功判定は rc + stderr のみ**。stdout が空（send-text / send-keys /
  ///   rename / close / split 等）でも rc=0 を成功とする（R7）。
  ///   stdout が非空なら応答 JSON から `changed` / `reason` / `layout` を抽出。
  /// - 失敗時は [_execChecked] と同じ分類:
  ///   - target-not-found → [HerdrTargetNotFoundException]
  ///   - `invalid_key` → errorCode 付き [HerdrCommandException]
  ///     （[isHerdrInvalidKey] で判定・防御的）
  ///   - それ以外 → [HerdrCommandException]
  /// - exitCode null かつ出力が空は SSH/transport 層の異常として
  ///   [SshConnectionError]（`isServerDownException` の server-down 分類へ）。
  Future<HerdrMutationResult> _execMutation(
    String command, {
    Duration? timeout,
  }) async {
    final resolved = _resolve(command);
    final result = await _backend.execWithExitCode(resolved, timeout: timeout);
    final stderr = result.stderr.trim();
    final exitCode = result.exitCode;

    if (exitCode == null && result.stdout.trim().isEmpty && stderr.isEmpty) {
      throw SshConnectionError(
        'Command channel closed without exit status or output: $resolved',
      );
    }

    if ((exitCode != null && exitCode != 0) || stderr.isNotEmpty) {
      final errorCode = _extractErrorCode(result);
      final kind = herdrTargetNotFoundKindForCode(errorCode);
      if (kind != null) {
        throw HerdrTargetNotFoundException(
          kind: kind,
          message: _buildErrorMessage(result),
          errorCode: errorCode,
          exitCode: exitCode,
        );
      }
      throw HerdrCommandException(
        _buildErrorMessage(result),
        exitCode: exitCode,
        errorCode: errorCode,
      );
    }
    return _parseMutationResult(result.stdout);
  }

  // inventory: HERDR-ADAPTER-031
  /// mutation 応答の stdout から [HerdrMutationResult] を抽出する。
  ///
  /// - stdout 空 → `changed:true` の素の成功（R7）。
  /// - JSON でない / 想定構造でない stdout → rc=0 を尊重し素の成功。
  /// - 応答形式（T0 実測 4-c/5-a/5-b/6-a）:
  ///   `{"result":{"resize":{"changed":..,"reason":..,"layout":{..}},"type":..}}`
  ///   操作サブオブジェクトは `changed` / `zoom_changed` / `layout` のいずれか
  ///   を持つものを探す（resize / focus / zoom / edges 共通）。
  HerdrMutationResult _parseMutationResult(String stdout) {
    if (stdout.trim().isEmpty) return const HerdrMutationResult();
    final Object? decoded;
    try {
      decoded = jsonDecode(stdout);
    } catch (_) {
      return const HerdrMutationResult();
    }
    if (decoded is! Map<String, dynamic>) return const HerdrMutationResult();
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) return const HerdrMutationResult();

    Map<String, dynamic>? op;
    for (final entry in result.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic> &&
          (value.containsKey('changed') ||
              value.containsKey('zoom_changed') ||
              value.containsKey('layout'))) {
        op = value;
        break;
      }
    }
    if (op == null) return const HerdrMutationResult();

    final changedRaw = op['changed'] ?? op['zoom_changed'];
    final changed = changedRaw is bool ? changedRaw : true;
    final reasonRaw = op['reason'];
    HerdrLayout? layout;
    final layoutRaw = op['layout'];
    if (layoutRaw is Map<String, dynamic>) {
      try {
        layout = HerdrSnapshotParser.parseLayoutMap(layoutRaw);
      } on FormatException {
        // 応答 layout の欠損は許容（rc=0 を優先・R7）。
        layout = null;
      }
    }
    return HerdrMutationResult(
      changed: changed,
      reason: reasonRaw is String ? reasonRaw : null,
      layout: layout,
    );
  }

  /// [command] 先頭の `herdr` をユーザー指定の実行ファイルパスに置換する。
  String _resolve(String command) {
    final path = _userExecutablePath?.trim();
    if (path == null || path.isEmpty) return command;
    return command.replaceFirst(RegExp(r'^herdr\b'), path);
  }

  /// [BackendAdapter.execWithExitCode] でコマンドを実行し、
  /// 非 0 終了・stderr 出力を例外に変換する。
  ///
  /// target-not-found 系 errorCode（`pane_not_found` / `tab_not_found` /
  /// `workspace_not_found`）なら [HerdrTargetNotFoundException] を、
  /// それ以外の失敗は [HerdrCommandException] を投げる。
  ///
  /// **exitCode null かつ stdout/stderr が空** の結果は「herdr コマンド失敗」
  /// ではなく SSH/transport 層の異常（チャネルが終了コードも出力も返さず
  /// 閉じた・接続断等）として [SshConnectionError] を投げる。これは
  /// [isServerDownException] で server-down に分類され、呼び出し側の再接続 /
  /// 通知ロジックに流れる。従来の「exitCode null → HerdrCommandException →
  /// No herdr pane found」と誤って swallow されるのを防ぐ（TERM-HERDR 診断）。
  ///
  /// exitCode null でも stdout が非空の場合は「出力は得られたが終了コードが
  /// 欠落した」とみなし、stdout を返す（後段のパーサが検証する）。
  Future<String> _execChecked(String command, {Duration? timeout}) async {
    final resolved = _resolve(command);
    final result = await _backend.execWithExitCode(resolved, timeout: timeout);
    final stderr = result.stderr.trim();
    final exitCode = result.exitCode;

    if (exitCode == null && result.stdout.trim().isEmpty && stderr.isEmpty) {
      throw SshConnectionError(
        'Command channel closed without exit status or output: $resolved',
      );
    }

    if ((exitCode != null && exitCode != 0) || stderr.isNotEmpty) {
      final errorCode = _extractErrorCode(result);
      final kind = herdrTargetNotFoundKindForCode(errorCode);
      if (kind != null) {
        throw HerdrTargetNotFoundException(
          kind: kind,
          message: _buildErrorMessage(result),
          errorCode: errorCode,
          exitCode: exitCode,
        );
      }
      throw HerdrCommandException(
        _buildErrorMessage(result),
        exitCode: exitCode,
        errorCode: errorCode,
      );
    }
    return result.stdout;
  }

  String _buildErrorMessage(
    ({String stdout, String stderr, int? exitCode}) result,
  ) {
    final stderr = result.stderr.trim();
    if (stderr.isNotEmpty) return 'herdr command failed: $stderr';
    final errorCode = _extractErrorCode(result);
    if (errorCode != null) {
      return 'herdr command failed: $errorCode (exit code: ${result.exitCode})';
    }
    // 診断: stdout が空かどうか・何バイトあったかを付与する（コマンドは
    // 出力したが終了コードが異常・欠落したケースの判別用）。A8 のプライバシー
    // 規則に従い、出力の内容（snapshot JSON 等）は含めずバイト数のみ記録する。
    final stdout = result.stdout.trim();
    final preview = stdout.isEmpty ? '' : ', stdout(${stdout.length}b)';
    return 'herdr command failed (exit code: ${result.exitCode}$preview)';
  }

  /// 構造化エラー JSON の `error.code` を stdout / stderr の両方から探す
  /// （無ければ null）。
  ///
  /// 出力形式（G4 実測）:
  /// `{"error":{"code":"workspace_not_found","message":"..."},"id":"cli:pane:get"}`
  /// CLI がエラーを stderr に書く実装もあるため、両方を対象にする。
  String? _extractErrorCode(
    ({String stdout, String stderr, int? exitCode}) result,
  ) {
    for (final text in [result.stdout, result.stderr]) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          final error = decoded['error'];
          if (error is Map<String, dynamic>) {
            final code = error['code'];
            if (code is String && code.isNotEmpty) return code;
          }
        }
      } catch (_) {
        // JSON でなければ無視
      }
    }
    return null;
  }
}

// inventory: HERDR-ADAPTER-020
/// mutation 実行結果。
///
/// `changed:false`（分割境界外 resize / 隣接なし focus 等）は失敗ではなく
/// **soft 失敗**（情報通知）を表す（S4 分類）。
class HerdrMutationResult {
  /// 状態が変化したかどうか。
  ///
  /// `changed:false`（resize の `reason:"unchanged"` / focus の
  /// `reason:"no_neighbor"` 等）で false。stdout が空の成功
  /// （send-text / send-keys / close / split / rename）は true。
  final bool changed;

  /// 応答の `reason`（`no_neighbor` / `unchanged` 等・無ければ null）。
  final String? reason;

  /// 応答に含まれるレイアウト（resize/zoom/focus/edges。無ければ null）。
  final HerdrLayout? layout;

  const HerdrMutationResult({
    this.changed = true,
    this.reason,
    this.layout,
  });

  /// 隣接 pane が無い（soft 失敗・情報通知）。
  bool get isNoNeighbor => reason == 'no_neighbor';

  /// 分割境界のため変更なし（soft 失敗・情報通知）。
  bool get isUnchanged => !changed;

  @override
  String toString() =>
      'HerdrMutationResult(changed: $changed, reason: $reason, '
      'layout: ${layout == null ? 'null' : 'present'})';
}
