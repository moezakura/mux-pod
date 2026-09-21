// inventory: HERDR-CARET-SSH-000
/// ephemeral SSH 実行の基盤。
///
/// [SshClient.execute] をラップし、実行層の失敗（切断・タイムアウト）を
/// 失敗分類（timeout / connectFailed）へ変換する。失敗報告（debug ログ +
/// throw）もここが担う。helper の install（SFTP）は [HerdrCaretInstaller]、
/// 実行は [HerdrCaretHelperExecutor] がこの runner を利用する。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../command/command_request.dart';
import '../../command/command_result.dart';
import '../../ssh/ssh_client.dart';
import 'herdr_caret_helper_types.dart';

/// helper 関連コマンドの SSH 実行基盤。
class HerdrCaretSshRunner {
  HerdrCaretSshRunner(this._ssh);

  final SshClient _ssh;

  /// ephemeral SSH でコマンドを実行する。
  ///
  /// 実行層の失敗（切断・タイムアウト）は [HerdrCaretHelperException] へ
  /// 分類する。コマンド文字列は機密情報（socket / pane / 出力内容）を
  /// 含みうるため、例外メッセージへは含めない。
  Future<CommandResult> exec(
    String command, {
    required Duration timeout,
  }) async {
    try {
      return await _ssh
          .execute(
            CommandRequest(
              command: command,
              transport: CommandTransportPreference.ephemeralOnly,
              output: CommandOutputRequirement.separatedOutput,
              timeout: timeout,
            ),
          )
          .timeout(timeout);
    } on TimeoutException {
      _fail(HerdrCaretHelperFailure.timeout, 'Command timed out');
    } on SshConnectionError catch (e) {
      if (e.message.toLowerCase().contains('timed out')) {
        _fail(HerdrCaretHelperFailure.timeout, 'Command timed out');
      }
      _fail(HerdrCaretHelperFailure.connectFailed, 'SSH command failed', e);
    } catch (e) {
      _fail(HerdrCaretHelperFailure.connectFailed, 'SSH command failed', e);
    }
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
}
