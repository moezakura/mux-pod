// inventory: HERDR-CARET-EXEC-000
/// 配置済み herdr-caret-helper の 1 回実行（snapshot 取得）を担う。
///
/// 処理フロー（Phase 3 契約・run 部分）:
/// shellQuote 済み引数でコマンドを構築 → ephemeral SSH で実行 → 出力検証
/// （JSON 単一行・64KB 打ち切り・exit code）。helper 実行は呼び出し毎に
/// 行い、実行頻度の制御（TTL・pane 単位 single-flight・epoch 照合）は
/// reader 側（[HerdrCaretHelperSnapshotReader]）が担うため、ここでは
/// single-flight しない。
library;

import 'package:flutter/foundation.dart';

import 'herdr_caret_helper_manifest.dart';
import 'herdr_caret_helper_types.dart';
import 'herdr_caret_shell_args.dart';
import 'herdr_caret_ssh.dart';

/// 配置済み helper の実行を担う executor。
class HerdrCaretHelperExecutor {
  /// helper stdout の最大長（これを超えた分は打ち切り）。
  static const int maxStdoutBytes = 64 * 1024;

  final HerdrCaretSshRunner _sshRunner;
  final HerdrCaretHelperManifest _manifest;

  HerdrCaretHelperExecutor({
    required HerdrCaretSshRunner sshRunner,
    required HerdrCaretHelperManifest manifest,
  }) : _sshRunner = sshRunner,
       _manifest = manifest;

  /// helper を 1 回実行する。
  ///
  /// manager 側では実行を single-flight しない（呼び出し毎に実行する）。
  /// 理由:
  /// - single-flight の契約は「同一 connection / pane / epoch」であり、
  ///   connection 単位で合流すると異なる pane の要求が混ざり、paneId 不一致の
  ///   stdout が返る（reader 側で stale として破棄されるだけで無駄になる）。
  /// - 実行頻度の制御（TTL・pane 単位 single-flight・epoch 照合・pane 切替時の
  ///   stale 破棄）は [HerdrCaretHelperSnapshotReader] が担う層にあり、
  ///   manager が connection 単位で合流すると reader の契約と重複・干渉する。
  /// - manager の memoize は install のみを対象とする。
  Future<String> runHelper(
    HerdrCaretInstallation installation, {
    required String clientSocket,
    required String paneId,
    required int cols,
    required int rows,
    required int protocol,
    required Duration timeout,
  }) {
    return _doRunHelper(
      installation,
      clientSocket: clientSocket,
      paneId: paneId,
      cols: cols,
      rows: rows,
      protocol: protocol,
      timeout: timeout,
    );
  }

  Future<String> _doRunHelper(
    HerdrCaretInstallation installation, {
    required String clientSocket,
    required String paneId,
    required int cols,
    required int rows,
    required int protocol,
    required Duration timeout,
  }) async {
    final command =
        '${HerdrCaretShellArgs.shellQuote(installation.remotePath)}'
        ' --socket ${HerdrCaretShellArgs.shellQuote(clientSocket)}'
        ' --pane ${HerdrCaretShellArgs.shellQuote(paneId)}'
        ' --protocol $protocol'
        ' --cols $cols'
        ' --rows $rows'
        ' --timeout-ms ${timeout.inMilliseconds}';
    final result = await _sshRunner.exec(command, timeout: timeout);

    if (result.exitCode != null && result.exitCode != 0) {
      _fail(
        HerdrCaretHelperFailure.execFailed,
        'Helper exited with ${result.exitCode}',
      );
    }

    var stdout = result.stdout.trim();
    if (stdout.length > maxStdoutBytes) {
      stdout = stdout.substring(0, maxStdoutBytes);
      _log('${_manifest.helperName}: stdout truncated');
    }
    if (stdout.isEmpty && result.exitCode == null) {
      _fail(HerdrCaretHelperFailure.connectFailed, 'Helper produced no output');
    }
    if (!stdout.startsWith('{') || !stdout.endsWith('}')) {
      _fail(
        HerdrCaretHelperFailure.invalidOutput,
        'Helper output is not a single JSON line',
      );
    }
    return stdout;
  }

  Never _fail(
    HerdrCaretHelperFailure failure,
    String message, [
    Object? cause,
  ]) {
    if (kDebugMode) {
      debugPrint('[herdr-caret] ${failure.name}: $message');
    }
    throw HerdrCaretHelperException(failure, message, cause);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[herdr-caret] $message');
    }
  }
}
