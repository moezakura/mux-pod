import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import '../command/command_request.dart';
import '../command/command_result.dart';
import '../connection_error.dart';
import 'persistent_shell.dart';

/// コマンド実行の執行者。**_execLock の単一所有者。**
///
/// [CommandRequest] の transport / output に基づく ephemeral / persistent
/// ルーティング・ephemeral チャネル実行・exec ロック・[PersistentShellError]
/// からのフォールバックを担う。シェル再起動は facade が配線した
/// [restartPollingShell] クロージャへ依頼するだけであり、shell manager を
/// 直接参照しない。routing 判定に必要な資源・l10n もクロージャ注入で解決する。
class SshCommandExecutor {
  SshCommandExecutor({
    required this.l10n,
    required this.isConnected,
    required this.client,
    required this.pollingShell,
    required this.restartPollingShell,
  });

  /// ローカライズ文字列プロバイダ（現在値を返すクロージャ）。
  final AppLocalizations? Function() l10n;

  /// 接続中かどうか（現在値を返すクロージャ）。
  final bool Function() isConnected;

  /// SSH トランスポート本体（現在値を返すクロージャ）。
  final SSHClient? Function() client;

  /// ポーリング用の持続的シェル（現在値を返すクロージャ）。
  final PersistentShell? Function() pollingShell;

  /// ポーリング用シェルの再起動依頼（facade 経由で shell manager へ配線）。
  final Future<void> Function() restartPollingShell;

  /// execチャネル排他制御用ロック
  Completer<void>? _execLock;

  /// 汎用コマンド実行（[CommandExecutor] 実装）。
  ///
  /// [CommandRequest.transport] / [CommandRequest.output] に基づいて
  /// ephemeral（毎回チャネル開閉）または persistent（持続的シェル）を
  /// ルーティングする（Codex 根本設計レビュー・バグ2 根本対応）。
  ///
  /// - `persistentPreferred + separatedOutput` は最初から ephemeral に
  ///   ルーティングする（PTY では分離できないため）。
  /// - `persistentOnly` は shell が利用不能なら例外を投げる。
  /// - timeout は `execute()` 全体の deadline。timeout 後の自動再実行はしない。
  Future<CommandResult> execute(CommandRequest request) async {
    if (!isConnected() || client() == null) {
      throw SshConnectionError(l10n()?.sshNotConnected ?? 'Not connected');
    }
    if (!request.isValid) {
      throw ArgumentError(
        'Invalid CommandRequest: persistentOnly + separatedOutput is impossible '
        '(PTY cannot separate stdout/stderr): $request',
      );
    }

    final useEphemeral =
        request.output == CommandOutputRequirement.separatedOutput ||
        request.transport == CommandTransportPreference.ephemeralOnly;

    if (useEphemeral) {
      final result = await _executeEphemeral(request);
      return CommandResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.separated,
        actualTransport: CommandTransport.ephemeral,
      );
    }

    // persistent 経路（outputOnly / exitCode・PTY では merged になる）。
    if (pollingShell() == null || !pollingShell()!.isStarted) {
      if (request.transport == CommandTransportPreference.persistentOnly) {
        throw SshConnectionError(
          l10n()?.sshPersistentShellUnavailable ??
              'Persistent shell is not available',
        );
      }
      final result = await _executeEphemeral(request);
      return CommandResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.separated,
        actualTransport: CommandTransport.ephemeral,
      );
    }

    final captureExitCode = request.output == CommandOutputRequirement.exitCode;
    try {
      final result = captureExitCode
          ? await pollingShell()!.execWithExitCode(
              request.command,
              timeout: request.timeout,
            )
          : (
              output: await pollingShell()!.exec(
                request.command,
                timeout: request.timeout,
              ),
              exitCode: null,
            );
      return CommandResult(
        mergedOutput: result.output,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.merged,
        actualTransport: CommandTransport.persistent,
      );
    } on PersistentShellError catch (e) {
      // シェルセッションが切断された場合のみ再起動して再試行する。
      // timeout（stale frame 混入防止で shell が破棄された）は自動再実行
      // しない（実行結果が不明のため・mutation の二重適用防止）。
      if (e.message.contains('closed') || e.message.contains('disposed')) {
        await restartPollingShell();
        final result = captureExitCode
            ? await pollingShell()!.execWithExitCode(
                request.command,
                timeout: request.timeout,
              )
            : (
                output: await pollingShell()!.exec(
                  request.command,
                  timeout: request.timeout,
                ),
                exitCode: null,
              );
        return CommandResult(
          mergedOutput: result.output,
          exitCode: result.exitCode,
          outputSeparation: CommandOutputSeparation.merged,
          actualTransport: CommandTransport.persistent,
        );
      }
      // その他の persistent エラー（persistentOnly はフォールバック不可）。
      if (request.transport == CommandTransportPreference.persistentOnly) {
        rethrow;
      }
      final result = await _executeEphemeral(request);
      return CommandResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.separated,
        actualTransport: CommandTransport.ephemeral,
      );
    }
  }

  /// ephemeral（毎回チャネル開閉 + exec ロック直列化）でコマンドを実行する。
  Future<({String stdout, String stderr, int? exitCode})> _executeEphemeral(
    CommandRequest request,
  ) async {
    if (!isConnected() || client() == null) {
      throw SshConnectionError(l10n()?.sshNotConnected ?? 'Not connected');
    }

    try {
      final resolvedCommand = request.command;
      return await _withExecLock(() async {
        // ignore: avoid_init_to_null
        SSHSession? session = null;
        // ignore: avoid_init_to_null
        int? exitCode = null;
        final stdoutBytes = <int>[];
        final stderrBytes = <int>[];
        try {
          session = await client()!.execute(resolvedCommand);

          final stdoutCompleter = Completer<void>();
          final stderrCompleter = Completer<void>();

          session.stdout.listen(
            (data) => stdoutBytes.addAll(data),
            onDone: () => stdoutCompleter.complete(),
            onError: (e) => stdoutCompleter.completeError(e),
          );

          session.stderr.listen(
            (data) => stderrBytes.addAll(data),
            onDone: () => stderrCompleter.complete(),
            onError: (e) => stderrCompleter.completeError(e),
          );

          if (request.timeout != null) {
            await Future.wait([
              stdoutCompleter.future,
              stderrCompleter.future,
            ]).timeout(request.timeout!);
          } else {
            await Future.wait([stdoutCompleter.future, stderrCompleter.future]);
          }

          exitCode = session.exitCode;
        } finally {
          session?.close();
        }

        return (
          stdout: utf8.decode(stdoutBytes, allowMalformed: true),
          stderr: utf8.decode(stderrBytes, allowMalformed: true),
          exitCode: exitCode,
        );
      });
    } on TimeoutException {
      throw SshConnectionError(
        l10n()?.sshCommandTimedOut ?? 'Command execution timed out',
      );
    } catch (e) {
      throw SshConnectionError(
        l10n()?.sshExecuteCommandFailed(e.toString()) ??
            'Failed to execute command: $e',
        e,
      );
    }
  }

  /// execチャネルを排他的に使用する
  Future<T> _withExecLock<T>(Future<T> Function() fn) async {
    while (_execLock != null) {
      await _execLock!.future;
    }
    final completer = Completer<void>();
    _execLock = completer;
    try {
      return await fn();
    } finally {
      _execLock = null;
      completer.complete();
    }
  }
}
