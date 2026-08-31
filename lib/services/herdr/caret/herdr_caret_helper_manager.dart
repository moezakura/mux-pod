// inventory: HERDR-CARET-MANAGER-000
/// SSH先への herdr-caret-helper の配置（content-addressed cache）と
/// 1回実行（snapshot取得）を担う manager。
///
/// 処理フロー（Phase 3 契約）:
/// 1. ephemeral SSH で `uname -s` / `uname -m` を取得し、manifest から
///    対応 platform を選ぶ（非 Linux・未知 arch は unsupported）。
/// 2. 設定済みの HerdrStatus.serverProtocol が 17/20 以外なら実行しない
///    （unsupportedProtocol）。
/// 3. HerdrStatus.socket を `derive_client_socket_from_api_socket` と同じ規則で
///    `*-client.sock` へ導出（null なら unsupported）。
/// 4. assets から helper バイナリを読み込み、sha256/size を検証する。
/// 5. 配置先 `${XDG_CACHE_HOME:-$HOME/.cache}/mux-pod/herdr-caret/<sha256>/`
///    に既存ファイルがあれば `sha256sum` で照合し、一致なら upload を skip。
/// 6. 不一致/無ければ SFTP で一時名へ upload → sha256/size 再検証 →
///    rename → `chmod 0700`。
/// 7. ephemeral SSH で helper を 1 回実行し、stdout（最大 64KB で打ち切り）を
///    返す。
///
/// install のみ connection 単位で memoize する（同一 connection での再配置を
/// 1 回にまとめる）。helper 実行は呼び出し毎に行い、実行頻度の制御
/// （TTL・pane 単位 single-flight・epoch 照合）は reader 側が担う。
///
/// セキュリティ規則（L1）: socket path・pane 本文・helper 出力の未検証内容を
/// 例外メッセージ・ログへ残さない。失敗分類だけを伝える。
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../command/command_request.dart';
import '../../command/command_result.dart';
import '../../sftp/sftp_service.dart';
import '../../ssh/ssh_client.dart';
import '../herdr_models.dart';
import 'herdr_caret_helper_manifest.dart';
import 'herdr_caret_snapshot.dart';

/// helper バイナリの読み込み（asset → バイト列）。
typedef HerdrCaretBinaryLoader = Future<Uint8List> Function(String assetPath);

/// 失敗分類。
enum HerdrCaretHelperFailure {
  /// 非対応環境（非 Linux・未知 arch・API socket 無し）。
  unsupported,

  /// Herdr serverProtocol が 17/20 以外。
  unsupportedProtocol,

  /// SSH 実行そのものが失敗（切断・基本コマンド不能など）。
  connectFailed,

  /// SFTP の open / mkdir / upload / rename が失敗。
  uploadFailed,

  /// helper バイナリの sha256/size が不一致（bundle 内・upload 後とも）。
  hashMismatch,

  /// helper / chmod が非ゼロ終了。
  execFailed,

  /// helper 実行がタイムアウト。
  timeout,

  /// helper 出力が単一 JSON 行でない・引数値が不正。
  invalidOutput,
}

/// helper 実行の失敗。
class HerdrCaretHelperException implements Exception {
  final HerdrCaretHelperFailure failure;
  final String message;

  /// 元の例外（任意。機密情報を含めないこと）。
  final Object? cause;

  const HerdrCaretHelperException(this.failure, this.message, [this.cause]);

  @override
  String toString() => 'HerdrCaretHelperException(${failure.name}): $message';
}

/// helper 1 回実行の結果。
class HerdrCaretHelperRunResult {
  /// helper が stdout へ書いた単一 JSON 行（最大 64KB）。
  final String stdout;

  /// 配置先のリモート絶対パス。
  final String remotePath;

  const HerdrCaretHelperRunResult({
    required this.stdout,
    required this.remotePath,
  });

  @override
  String toString() =>
      'HerdrCaretHelperRunResult(remotePath=$remotePath, '
      'stdout=${stdout.length} chars)';
}

/// 配置済み helper の情報。
class HerdrCaretInstallation {
  final String remotePath;
  final String sha256;

  const HerdrCaretInstallation({
    required this.remotePath,
    required this.sha256,
  });
}

/// snapshot reader（Phase 4）から注入される helper 実行抽象。
///
/// テストではこの interface を fake する。
abstract interface class HerdrCaretHelperRunner {
  /// [status] の protocol / socket に基づき、[paneId] のカーソル snapshot
  /// を helper 1 回実行で取得する。
  ///
  /// 失敗は [HerdrCaretHelperException] を投げる。
  Future<HerdrCaretHelperRunResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    Duration? timeout,
  });
}

/// SSH/SFTP 経由で helper を配置・実行する manager。
///
/// テストでは [SshClient]（[FakeSshClient]）・[SftpClient]・
/// [HerdrCaretBinaryLoader] を差し替えて挙動を検証する。
class HerdrCaretHelperManager implements HerdrCaretHelperRunner {
  /// helper stdout の最大長（これを超えた分は打ち切り）。
  static const int maxStdoutBytes = 64 * 1024;

  /// 既定の helper 実行タイムアウト。
  static const Duration defaultRunTimeout = Duration(milliseconds: 1000);

  /// リモート配置ディレクトリ（cache base 配下）。
  static const String remoteInstallDir = 'mux-pod/herdr-caret';

  /// helper 配置後のパーミッション（rwx------）。
  static const String remoteFileMode = '0700';

  final SshClient _ssh;
  final HerdrCaretHelperManifest _manifest;
  final HerdrCaretBinaryLoader _binaryLoader;
  final SftpService _sftpService;

  /// connection 単位の install memo（同一 connection で再 install しない）。
  final Map<Object, Future<HerdrCaretInstallation>> _installMemo = {};

  HerdrCaretHelperManager({
    required SshClient ssh,
    required HerdrCaretHelperManifest manifest,
    HerdrCaretBinaryLoader? binaryLoader,
    SftpService? sftpService,
  }) : _ssh = ssh,
       _manifest = manifest,
       _binaryLoader = binaryLoader ?? _rootBundleLoad,
       _sftpService = sftpService ?? SftpService();

  static Future<Uint8List> _rootBundleLoad(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// サポートする Herdr protocol 番号（17 / 20 のみ）。
  static const Set<int> supportedProtocols = kHerdrCaretSupportedProtocols;

  /// API socket（`herdr status --json` の `server.socket`）から
  /// client socket を導出する。
  ///
  /// `derive_client_socket_from_api_socket` と同じ規則:
  /// 同ディレクトリの `file_stem + "-client.sock"`。
  /// dirname が `.`（bare ファイル名）の場合は `./` を付けずに返す。
  static String deriveClientSocket(String apiSocket) {
    final dir = p.posix.dirname(apiSocket);
    final stem = p.posix.basenameWithoutExtension(apiSocket);
    final name = '$stem-client.sock';
    return dir == '.' ? name : p.posix.join(dir, name);
  }

  /// pane ID の書式検証（長さ 1..64・印字可能 ASCII・制御文字なし）。
  ///
  /// 書式をクライアント側で捏造せず、この検証を通過した値だけを
  /// shell 引数として使う。
  static bool isValidPaneId(String paneId) {
    if (paneId.isEmpty || paneId.length > 64) return false;
    for (final unit in paneId.codeUnits) {
      if (unit < 0x20 || unit > 0x7E) return false;
    }
    return true;
  }

  /// POSIX single-quote エスケープ（`'...'` 内の `'` は `'\''`）。
  static String shellQuote(String arg) => "'${arg.replaceAll("'", r"'\''")}'";

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
    if (!supportedProtocols.contains(status.serverProtocol)) {
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
    if (!isValidPaneId(paneId)) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid pane id format');
    }
    if (cols < 0 || cols > 0xFFFF || rows < 0 || rows > 0xFFFF) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid frame size');
    }

    final clientSocket = deriveClientSocket(apiSocket);
    final installation = await _ensureInstalled(execTimeout);
    final stdout = await _runHelper(
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

  // ===== installation =====

  /// 配置を connection 単位で memoize + single-flight する。
  ///
  /// 失敗時は memo から除去し、次の要求で再試行できるようにする。
  Future<HerdrCaretInstallation> _ensureInstalled(Duration timeout) {
    final existing = _installMemo[_ssh];
    if (existing != null) return existing;
    final future = _install(timeout);
    _installMemo[_ssh] = future;
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_installMemo[_ssh], future)) {
          _installMemo.remove(_ssh);
        }
      },
    );
    return future;
  }

  Future<HerdrCaretInstallation> _install(Duration timeout) async {
    // 1. uname で platform 判定
    final osResult = await _exec('uname -s', timeout: timeout);
    _requireExitCodeZero(
      osResult,
      'uname -s',
      HerdrCaretHelperFailure.connectFailed,
    );
    final os = osResult.stdout.trim();
    final archResult = await _exec('uname -m', timeout: timeout);
    _requireExitCodeZero(
      archResult,
      'uname -m',
      HerdrCaretHelperFailure.connectFailed,
    );
    final arch = archResult.stdout.trim();
    if (os.isEmpty || arch.isEmpty) {
      _fail(
        HerdrCaretHelperFailure.connectFailed,
        'Unable to determine remote platform',
      );
    }

    // 2. manifest から platform 選択
    final platform = _manifest.selectFor(os, arch);
    if (platform == null) {
      _fail(
        HerdrCaretHelperFailure.unsupported,
        'Platform is not supported: '
        '${HerdrCaretHelperManifest.normalizeOs(os)}'
        '/${HerdrCaretHelperManifest.normalizeArch(arch)}',
      );
    }

    // 3. bundle からバイナリを読み込み sha256/size 検証
    final Uint8List bytes;
    try {
      bytes = await _binaryLoader(platform.asset);
    } catch (e) {
      _fail(
        HerdrCaretHelperFailure.uploadFailed,
        'Failed to load helper asset from bundle',
        e,
      );
    }
    if (!platform.matchesBytes(bytes)) {
      _fail(
        HerdrCaretHelperFailure.hashMismatch,
        'Bundled helper does not match manifest',
      );
    }
    final expectedSha = platform.sha256.toLowerCase();

    // 4. リモート cache base を env から取得
    final baseResult = await _exec(
      // m1 修正: `\n` はシェルの非クォート部でエスケープ除去され `n` になる
      // ため、フォーマットをクォートする（実シェル検証済み）。
      "printf '%s\\n' \"\${XDG_CACHE_HOME:-\$HOME/.cache}\"",
      timeout: timeout,
    );
    _requireExitCodeZero(
      baseResult,
      'cache base',
      HerdrCaretHelperFailure.connectFailed,
    );
    final base = baseResult.stdout.trim();
    if (base.isEmpty) {
      _fail(
        HerdrCaretHelperFailure.connectFailed,
        'Remote cache base is unavailable',
      );
    }

    final remoteDir = p.posix.join(base, remoteInstallDir, expectedSha);
    final remotePath = p.posix.join(remoteDir, _manifest.helperName);

    // 5. 既存ファイルの sha256sum 照合（一致なら upload skip）
    final sumResult = await _exec(
      'sha256sum ${shellQuote(remotePath)}',
      timeout: timeout,
    );
    if (sumResult.exitCode == 0) {
      final existingHash = _parseSha256Output(sumResult.stdout);
      if (existingHash == expectedSha) {
        _log('${_manifest.helperName}: ready (cached)');
        return HerdrCaretInstallation(
          remotePath: remotePath,
          sha256: expectedSha,
        );
      }
    }
    _log('${_manifest.helperName}: installing');

    // 6. SFTP で一時名へ upload → sha256/size 再検証 → rename
    final tempPath = p.posix.join(remoteDir, '.${_manifest.helperName}.tmp');
    await _installRemote(
      sftpBytes: bytes,
      platform: platform,
      remoteDir: remoteDir,
      tempPath: tempPath,
      remotePath: remotePath,
      timeout: timeout,
    );

    // 7. chmod 0700
    final chmodResult = await _exec(
      'chmod $remoteFileMode ${shellQuote(remotePath)}',
      timeout: timeout,
    );
    if (chmodResult.exitCode != null && chmodResult.exitCode != 0) {
      _fail(
        HerdrCaretHelperFailure.execFailed,
        'Failed to set helper permissions',
      );
    }

    _log('${_manifest.helperName}: ready (installed)');
    return HerdrCaretInstallation(remotePath: remotePath, sha256: expectedSha);
  }

  Future<void> _installRemote({
    required Uint8List sftpBytes,
    required HerdrCaretHelperPlatform platform,
    required String remoteDir,
    required String tempPath,
    required String remotePath,
    required Duration timeout,
  }) async {
    final SftpClient sftp;
    try {
      sftp = await _ssh.openSftp();
    } catch (e) {
      _fail(
        HerdrCaretHelperFailure.uploadFailed,
        'Failed to open SFTP session',
        e,
      );
    }

    try {
      await _sftpService.ensureDirectory(sftp, remoteDir);
    } catch (e) {
      _fail(
        HerdrCaretHelperFailure.uploadFailed,
        'Failed to create remote directory',
        e,
      );
    }

    try {
      await _sftpService.uploadStream(
        sftp: sftp,
        remoteDir: remoteDir,
        filename: p.posix.basename(tempPath),
        source: Stream.value(sftpBytes),
        totalBytes: sftpBytes.length,
      );
    } catch (e) {
      _fail(HerdrCaretHelperFailure.uploadFailed, 'Failed to upload helper', e);
    }

    // upload 後の sha256 / size 再検証（一時ファイルを対象にする）
    final sumResult = await _exec(
      'sha256sum ${shellQuote(tempPath)}',
      timeout: timeout,
    );
    final remoteHash = sumResult.exitCode == 0
        ? _parseSha256Output(sumResult.stdout)
        : null;
    int? remoteSize;
    try {
      remoteSize = (await sftp.stat(tempPath)).size;
    } catch (_) {
      remoteSize = null;
    }
    if (remoteHash != platform.sha256.toLowerCase() ||
        remoteSize != platform.size) {
      try {
        await sftp.remove(tempPath);
      } catch (_) {
        // クリーンアップ失敗は無視
      }
      _fail(
        HerdrCaretHelperFailure.hashMismatch,
        'Remote helper hash/size mismatch after upload',
      );
    }

    try {
      await sftp.rename(tempPath, remotePath);
    } catch (e) {
      _fail(
        HerdrCaretHelperFailure.uploadFailed,
        'Failed to move helper into place',
        e,
      );
    }
  }

  /// `sha256sum` 出力から先頭トークン（小文字 hex）を取り出す。
  ///
  /// 形式不正なら null。
  static String? _parseSha256Output(String output) {
    final token = output.trim().split(RegExp(r'\s+')).firstOrNull;
    if (token == null || token.length != 64) return null;
    for (final unit in token.codeUnits) {
      final isHexDigit =
          (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x66);
      if (!isHexDigit) return null;
    }
    return token;
  }

  void _requireExitCodeZero(
    CommandResult result,
    String what,
    HerdrCaretHelperFailure failure,
  ) {
    if (result.exitCode != null && result.exitCode != 0) {
      _fail(failure, '$what exited with ${result.exitCode}');
    }
  }

  // ===== run =====

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
  /// - manager の memoize は install（[_ensureInstalled]）のみを対象とする。
  Future<String> _runHelper(
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
        '${shellQuote(installation.remotePath)}'
        ' --socket ${shellQuote(clientSocket)}'
        ' --pane ${shellQuote(paneId)}'
        ' --protocol $protocol'
        ' --cols $cols'
        ' --rows $rows'
        ' --timeout-ms ${timeout.inMilliseconds}';
    final result = await _exec(command, timeout: timeout);

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

  // ===== infrastructure =====

  /// ephemeral SSH でコマンドを実行する。
  ///
  /// 実行層の失敗（切断・タイムアウト）は [HerdrCaretHelperException] へ
  /// 分類する。コマンド文字列は機密情報（socket / pane / 出力内容）を
  /// 含みうるため、例外メッセージへは含めない。
  Future<CommandResult> _exec(
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

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[herdr-caret] $message');
    }
  }
}
