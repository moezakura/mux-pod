// inventory: HERDR-EXEC-000
/// herdr CLI への exec 基盤（read / mutation 共通）。
///
/// [BackendAdapter] 経由で herdr CLI を実行し、エラーを target-not-found /
/// command / SSH 切断に分類して例外化する。[HerdrReadClient]（read）と
/// [HerdrMutationClient]（mutation）の両方がこの exec 基盤へ委譲する。
/// ローカライズは [HerdrCommandExecutor.strings] で遅延解決する
/// （`_l10n ?? lookupL10n()`。言語切替後に最新値が反映される）。
library;

import 'dart:async';
import 'dart:convert';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_lookup.dart';
import '../backend/backend_adapter.dart';
import '../command/command_request.dart';
import '../command/command_result.dart';
import '../connection_error.dart';
import 'herdr_commands.dart';
import 'herdr_errors.dart';

/// herdr CLI へのアクセスを提供する exec 基盤（read / mutation 共通）。
///
/// 送信は [_resolve] で userExecutablePath を適用し、失敗は
/// [HerdrTargetNotFoundException] / [HerdrCommandException] /
/// [SshConnectionError] に分類して投げる。
class HerdrCommandExecutor {
  final BackendAdapter _backend;
  final String? _userExecutablePath;

  /// 任意のローカライズ文字列。null の場合は英語フォールバック（テスト互換）。
  final AppLocalizations? _l10n;

  /// 解決済みローカライズ文字列。未指定時は設定言語キャッシュから解決する。
  AppLocalizations get _strings => _l10n ?? lookupL10n();

  /// read / mutation 側が例外メッセージ構築に使うローカライズ文字列。
  ///
  /// [_strings]（遅延解決）を公開したもの。アクセス時点の最新値が返る。
  AppLocalizations get strings => _strings;

  HerdrCommandExecutor(
    this._backend, {
    String? userExecutablePath,
    AppLocalizations? l10n,
  }) : _userExecutablePath = userExecutablePath ?? _backend.userExecutablePath,
       _l10n = l10n;

  /// 接続中かどうか。
  bool get isConnected => _backend.isConnected;

  /// 入力専用の持続的シェルへコマンドを fire-and-forget 送信する。
  ///
  /// 入力シェルが無い・開始前・送信失敗（[BackendTransportException]・シェル
  /// 切断）の場合は false を返す。送信失敗時は [_backend.restartInputTransport]
  /// で回復を試みる（tmux の `sendKeysCommand` と同じ方針）。
  /// 成功（true）の場合、呼び出し側は exec フォールバックをしない。
  bool trySendNoWait(String command) {
    final input = _backend.inputTransport;
    if (input == null || !input.isStarted) return false;
    try {
      input.sendNoWait(_resolve(command));
      return true;
    } on BackendTransportException {
      unawaited(_backend.restartInputTransport());
      return false;
    }
  }

  /// mutation コマンドを実行し、成功時は応答 stdout を返す。
  ///
  /// - **成功判定は rc + stderr のみ**。stdout が空（send-text / send-keys /
  ///   rename / close / split 等）でも rc=0 を成功とする（R7）。
  ///   stdout が非空なら応答 JSON から `changed` / `reason` / `layout` を
  ///   抽出する（解析は [HerdrMutationResult.parse] が行う）。
  /// - 失敗時は [execChecked] と同じ分類:
  ///   - target-not-found → [HerdrTargetNotFoundException]
  ///   - `invalid_key` → errorCode 付き [HerdrCommandException]
  ///     （[isHerdrInvalidKey] で判定・防御的）
  ///   - それ以外 → [HerdrCommandException]
  /// - exitCode null かつ出力が空は SSH/transport 層の異常として
  ///   [SshConnectionError]（`isServerDownException` の server-down 分類へ）。
  Future<String> execMutation(String command, {Duration? timeout}) async {
    final resolved = _resolve(command);
    final result = await _backend.execute(
      CommandRequest(
        command: resolved,
        transport: CommandTransportPreference.ephemeralOnly,
        output: CommandOutputRequirement.separatedOutput,
        timeout: timeout,
      ),
    );
    final stderr = result.stderr.trim();
    final exitCode = result.exitCode;

    if (exitCode == null && result.stdout.trim().isEmpty && stderr.isEmpty) {
      throw SshConnectionError(_strings.connHerdrChannelClosed(resolved));
    }

    if ((exitCode != null && exitCode != 0) || stderr.isNotEmpty) {
      final errorCode = _extractErrorCodeFrom(result);
      final kind = herdrTargetNotFoundKindForCode(errorCode);
      if (kind != null) {
        throw HerdrTargetNotFoundException(
          kind: kind,
          message: _buildErrorMessageFrom(result),
          errorCode: errorCode,
          exitCode: exitCode,
        );
      }
      throw HerdrCommandException(
        _buildErrorMessageFrom(result),
        exitCode: exitCode,
        errorCode: errorCode,
      );
    }
    return result.stdout;
  }

  /// [CommandExecutor.execute] でコマンドを実行し、非 0 終了・エラー出力を
  /// 例外に変換する（read 用）。
  ///
  /// target-not-found 系 errorCode（`pane_not_found` / `tab_not_found` /
  /// `workspace_not_found`）なら [HerdrTargetNotFoundException] を、
  /// それ以外の失敗は [HerdrCommandException] を投げる。
  ///
  /// **exitCode null かつ出力が空** の結果は「herdr コマンド失敗」
  /// ではなく SSH/transport 層の異常（チャネルが終了コードも出力も返さず
  /// 閉じた・接続断等）として [SshConnectionError] を投げる。これは
  /// [isServerDownException] で server-down に分類され、呼び出し側の再接続 /
  /// 通知ロジックに流れる。従来の「exitCode null → HerdrCommandException →
  /// No herdr pane found」と誤って swallow されるのを防ぐ（TERM-HERDR 診断）。
  ///
  /// exitCode null でも出力が非空の場合は「出力は得られたが終了コードが
  /// 欠落した」とみなし、出力を返す（後段のパーサが検証する）。
  ///
  /// [viaPersistent] は persistent shell 経由（チャネル再利用 + exec ロック
  /// 回避・バグ2）で実行する。persistent 経路の結果は merged（PTY）で、
  /// エラー分類は exit code + [CommandResult.primaryOutput] 由来の errorCode
  /// 抽出で維持される（target-not-found / server-down）。ephemeral 経路は
  /// separated（stdout/stderr 分離）でエラー分類する。
  Future<String> execChecked(
    String command, {
    Duration? timeout,
    bool viaPersistent = false,
  }) async {
    final resolved = _resolve(command);
    final result = await _backend.execute(
      CommandRequest(
        command: resolved,
        transport: viaPersistent
            ? CommandTransportPreference.persistentPreferred
            : CommandTransportPreference.ephemeralOnly,
        output: viaPersistent
            ? CommandOutputRequirement.exitCode
            : CommandOutputRequirement.separatedOutput,
        timeout: timeout,
      ),
    );
    final stderr = result.stderr.trim();
    final exitCode = result.exitCode;
    final primary = result.primaryOutput;

    if (exitCode == null && primary.trim().isEmpty && stderr.isEmpty) {
      throw SshConnectionError(_strings.connHerdrChannelClosed(resolved));
    }

    if ((exitCode != null && exitCode != 0) || stderr.isNotEmpty) {
      final errorCode = _extractErrorCodeFrom(result);
      final kind = herdrTargetNotFoundKindForCode(errorCode);
      if (kind != null) {
        throw HerdrTargetNotFoundException(
          kind: kind,
          message: _buildErrorMessageFrom(result),
          errorCode: errorCode,
          exitCode: exitCode,
        );
      }
      throw HerdrCommandException(
        _buildErrorMessageFrom(result),
        exitCode: exitCode,
        errorCode: errorCode,
      );
    }
    return primary;
  }

  /// [command] 先頭の `herdr` をユーザー指定の実行ファイルパスに置換する。
  String _resolve(String command) {
    final path = _userExecutablePath?.trim();
    if (path == null || path.isEmpty) return command;
    return command.replaceFirst(RegExp(r'^herdr\b'), path);
  }

  /// [CommandResult] からエラーメッセージを組み立てる。
  ///
  /// merged 経路では stderr が primaryOutput に混ざるため、stderr 単独で
  /// なく primaryOutput も対象にする（バグ2 根本対応）。
  String _buildErrorMessageFrom(CommandResult result) {
    final stderr = result.stderr.trim();
    if (stderr.isNotEmpty) {
      return _strings.connHerdrCommandFailed(stderr);
    }
    final errorCode = _extractErrorCodeFrom(result);
    if (errorCode != null) {
      // エラーコードはサーバー由来（machine-readable）のためローカライズせず、
      // プレフィックス部のみキー化する。元リテラルとの完全互換のため
      // exitCode は null を含めて文字列化して渡す。
      return _strings.connHerdrCommandFailedErrorCode(
        errorCode,
        '${result.exitCode}',
      );
    }
    // 診断: 出力が空かどうか・何バイトあったかを付与する（コマンドは
    // 出力したが終了コードが異常・欠落したケースの判別用）。A8 のプライバシー
    // 規則に従い、出力の内容（snapshot JSON 等）は含めずバイト数のみ記録する。
    final primary = result.primaryOutput.trim();
    if (primary.isEmpty) {
      return _strings.connHerdrCommandFailedExitCode('${result.exitCode}');
    }
    return _strings.connHerdrCommandFailedExitCodePreview(
      '${result.exitCode}',
      primary.length,
    );
  }

  /// 構造化エラー JSON の `error.code` を stdout / stderr の両方から探す
  /// （無ければ null）。
  ///
  /// 出力形式（G4 実測）:
  /// `{"error":{"code":"workspace_not_found","message":"..."},"id":"cli:pane:get"}`
  /// CLI がエラーを stderr に書く実装もあるため、両方を対象にする。
  /// merged 経路では primaryOutput にエラー JSON が混ざるため、それも対象
  /// にする（バグ2 根本対応）。
  String? _extractErrorCodeFrom(CommandResult result) {
    final candidates = <String>[
      result.stdout,
      result.stderr,
      result.primaryOutput,
    ];
    for (final text in candidates) {
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
