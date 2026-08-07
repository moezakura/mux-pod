// inventory: HERDR-ADAPTER-000
/// SSH 経由で herdr CLI を実行する adapter（read-only）。
///
/// 既存の [BackendAdapter] をラップし、CLI 先行方式で herdr の JSON 返却
/// コマンドを実行・パースする。mutation コマンドは本 milestone では実装・
/// 公開しない（socket 直結は次の milestone）。
library;

import 'dart:convert';

import '../backend/backend_adapter.dart';
import 'herdr_commands.dart';
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
  /// 非 0 終了・stderr 出力を [HerdrCommandException] に変換する。
  Future<String> _execChecked(String command, {Duration? timeout}) async {
    final result = await _backend.execWithExitCode(
      _resolve(command),
      timeout: timeout,
    );
    if (result.exitCode != 0 || result.stderr.trim().isNotEmpty) {
      throw HerdrCommandException(
        _buildErrorMessage(result),
        exitCode: result.exitCode,
      );
    }
    return result.stdout;
  }

  String _buildErrorMessage(
    ({String stdout, String stderr, int? exitCode}) result,
  ) {
    final stderr = result.stderr.trim();
    if (stderr.isNotEmpty) return 'herdr command failed: $stderr';
    final errorCode = _extractErrorCode(result.stdout);
    if (errorCode != null) {
      return 'herdr command failed: $errorCode (exit code: ${result.exitCode})';
    }
    return 'herdr command failed (exit code: ${result.exitCode})';
  }

  /// 構造化エラー JSON の `error.code` を取り出す（無ければ null）。
  ///
  /// 出力形式（G4 実測）:
  /// `{"error":{"code":"workspace_not_found","message":"..."},"id":"cli:pane:get"}`
  String? _extractErrorCode(String stdout) {
    try {
      final decoded = jsonDecode(stdout);
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
    return null;
  }
}
