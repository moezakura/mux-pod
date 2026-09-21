// inventory: HERDR-CARET-MANAGER-000
/// SSH先への herdr-caret-helper の配置（content-addressed cache）と
/// 1回実行（snapshot取得）を担う runner interface 実装のオーケストレーター。
///
/// 処理フロー（Phase 3 契約）:
/// 1. HerdrStatus.serverProtocol が 17/20 以外なら実行しない
///    （unsupportedProtocol）。
/// 2. HerdrStatus.socket を `derive_client_socket_from_api_socket` と同じ規則で
///    `*-client.sock` へ導出（null なら unsupported）。
/// 3. paneId / frame size の形式検証（不正は invalidOutput）。
/// 4. installer に helper 配置を依頼（connection 単位 memoize・sha256sum
///    照合・SFTP upload・chmod は installer の責務）。
/// 5. executor に helper を 1 回実行させ、stdout（最大 64KB で打ち切り）を
///    返す。
///
/// 本クラスは検証と順序制御のみを行い、install は [HerdrCaretInstaller]、
/// 実行は [HerdrCaretHelperExecutor]、SSH 実行基盤は [HerdrCaretSshRunner]
/// へ委譲する。installer は Manager と 1:1 で生成され、SshClient 差し替え時も
/// memo は `_ssh` identity で自動追従する（接続単位を「インスタンス単位」に
/// 読み替えない・同一インスタンスへの再 install を防ぐだけ）。
///
/// セキュリティ規則（L1）: socket path・pane 本文・helper 出力の未検証内容を
/// 例外メッセージ・ログへ残さない。失敗分類だけを伝える。
library;

import 'package:flutter/foundation.dart';

import '../../sftp/sftp_service.dart';
import '../../ssh/ssh_client.dart';
import '../herdr_models.dart';
import '../herdr_version.dart';
import 'herdr_caret_helper_executor.dart';
import 'herdr_caret_helper_installer.dart';
import 'herdr_caret_helper_manifest.dart';
import 'herdr_caret_helper_types.dart';
import 'herdr_caret_shell_args.dart';
import 'herdr_caret_ssh.dart';

export 'herdr_caret_helper_types.dart';

/// SSH/SFTP 経由で helper を配置・実行する manager。
///
/// テストでは [SshClient]（[FakeSshClient]）・[SftpClient]・
/// [HerdrCaretBinaryLoader] を差し替えて挙動を検証する。
class HerdrCaretHelperManager implements HerdrCaretHelperRunner {
  /// helper stdout の最大長（これを超えた分は打ち切り）。
  static const int maxStdoutBytes = HerdrCaretHelperExecutor.maxStdoutBytes;

  /// 既定の helper 実行タイムアウト。
  static const Duration defaultRunTimeout = Duration(milliseconds: 1000);

  late final HerdrCaretSshRunner _sshRunner;
  late final HerdrCaretInstaller _installer;
  late final HerdrCaretHelperExecutor _executor;

  HerdrCaretHelperManager({
    required SshClient ssh,
    required HerdrCaretHelperManifest manifest,
    HerdrCaretBinaryLoader? binaryLoader,
    SftpService? sftpService,
  }) {
    _sshRunner = HerdrCaretSshRunner(ssh);
    _installer = HerdrCaretInstaller(
      ssh: ssh,
      manifest: manifest,
      sshRunner: _sshRunner,
      binaryLoader: binaryLoader ?? HerdrCaretInstaller.rootBundleLoad,
      sftpService: sftpService ?? SftpService(),
    );
    _executor = HerdrCaretHelperExecutor(
      sshRunner: _sshRunner,
      manifest: manifest,
    );
  }

  @override
  Future<HerdrCaretHelperRunResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    Duration? timeout,
  }) async {
    final execTimeout = timeout ?? defaultRunTimeout;

    // protocol は helper 実行前に判定（17/20 以外は配置・実行しない）。
    if (!isHerdrCaretProtocolSupported(status.serverProtocol)) {
      _fail(
        HerdrCaretHelperFailure.unsupportedProtocol,
        'Server protocol ${status.serverProtocol} is not supported',
      );
    }

    // API socket が無ければ非対応扱い。
    final apiSocket = status.socket;
    if (apiSocket == null || apiSocket.trim().isEmpty) {
      _fail(
        HerdrCaretHelperFailure.unsupported,
        'Herdr API socket is unavailable',
      );
    }

    // pane ID は検証を通った値だけを shell 引数へ流す。
    if (!HerdrCaretShellArgs.isValidPaneId(paneId)) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid pane id format');
    }
    if (cols < 0 || cols > 0xFFFF || rows < 0 || rows > 0xFFFF) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid frame size');
    }

    final clientSocket = HerdrCaretShellArgs.deriveClientSocket(apiSocket);
    final installation = await _installer.ensureInstalled(execTimeout);
    final stdout = await _executor.runHelper(
      installation,
      clientSocket: clientSocket,
      paneId: paneId,
      cols: cols,
      rows: rows,
      protocol: status.serverProtocol,
      timeout: execTimeout,
    );
    return HerdrCaretHelperRunResult(
      stdout: stdout,
      remotePath: installation.remotePath,
    );
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
