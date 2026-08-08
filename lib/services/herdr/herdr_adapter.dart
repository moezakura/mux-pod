// inventory: HERDR-ADAPTER-000
/// SSH 経由で herdr CLI を実行する adapter（read-only）。
///
/// 既存の [BackendAdapter] をラップし、CLI 先行方式で herdr の JSON 返却
/// コマンドを実行・パースする。mutation コマンドは本 milestone では実装・
/// 公開しない（socket 直結は次の milestone）。
library;

import 'dart:convert';

import '../backend/backend_adapter.dart';
import '../connection_error.dart';
import 'herdr_commands.dart';
import 'herdr_errors.dart';
import 'herdr_models.dart';
import 'herdr_parser.dart';

// inventory: HERDR-ADAPTER-001
/// herdr CLI への read-only アクセスを提供する adapter。
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
