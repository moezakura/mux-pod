// inventory: HERDR-CARET-INSTALL-000
/// herdr-caret-helper のリモート配置（content-addressed cache）を担う。
///
/// 処理フロー（Phase 3 契約・install 部分）:
/// 1. ephemeral SSH で `uname -s` / `uname -m` を取得し、manifest から
///    対応 platform を選ぶ（非 Linux・未知 arch は unsupported）。
/// 2. assets から helper バイナリを読み込み、sha256/size を検証する。
/// 3. 配置先 `${XDG_CACHE_HOME:-$HOME/.cache}/mux-pod/herdr-caret/<sha256>/`
///    に既存ファイルがあれば `sha256sum` で照合し、一致なら upload を skip。
/// 4. 不一致/無ければ SFTP で一時名へ upload → sha256/size 再検証 →
///    rename → `chmod 0700`。
///
/// install のみ connection 単位で memoize する（同一 connection での再配置を
/// 1 回にまとめる）。**memo の key は SshClient インスタンス**（`_ssh`
/// identity・`identical` 比較）。Manager が複数 connection を差し替えても
/// 別インスタンスは別 key として new install される。失敗時は memo から
/// 除去し、次の要求で再試行できるようにする。
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../command/command_result.dart';
import '../../sftp/sftp_service.dart';
import '../../ssh/ssh_client.dart';
import 'herdr_caret_helper_manifest.dart';
import 'herdr_caret_helper_types.dart';
import 'herdr_caret_shell_args.dart';
import 'herdr_caret_ssh.dart';

/// helper のリモート配置を担う installer。
class HerdrCaretInstaller {
  /// リモート配置ディレクトリ（cache base 配下）。
  static const String remoteInstallDir = 'mux-pod/herdr-caret';

  /// helper 配置後のパーミッション（rwx------）。
  static const String remoteFileMode = '0700';

  final SshClient _ssh;
  final HerdrCaretHelperManifest _manifest;
  final HerdrCaretBinaryLoader _binaryLoader;
  final SftpService _sftpService;
  final HerdrCaretSshRunner _sshRunner;

  /// connection 単位の install memo（同一 connection で再 install しない）。
  final Map<Object, Future<HerdrCaretInstallation>> _installMemo = {};

  HerdrCaretInstaller({
    required SshClient ssh,
    required HerdrCaretHelperManifest manifest,
    required HerdrCaretSshRunner sshRunner,
    HerdrCaretBinaryLoader? binaryLoader,
    SftpService? sftpService,
  }) : _ssh = ssh,
       _manifest = manifest,
       _sshRunner = sshRunner,
       _binaryLoader = binaryLoader ?? rootBundleLoad,
       _sftpService = sftpService ?? SftpService();

  static Future<Uint8List> rootBundleLoad(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// 配置を connection 単位で memoize + single-flight する。
  ///
  /// 失敗時は memo から除去し、次の要求で再試行できるようにする。
  Future<HerdrCaretInstallation> ensureInstalled(Duration timeout) {
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
    final osResult = await _sshRunner.exec('uname -s', timeout: timeout);
    _requireExitCodeZero(
      osResult,
      'uname -s',
      HerdrCaretHelperFailure.connectFailed,
    );
    final os = osResult.stdout.trim();
    final archResult = await _sshRunner.exec('uname -m', timeout: timeout);
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
    final baseResult = await _sshRunner.exec(
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
    final sumResult = await _sshRunner.exec(
      'sha256sum ${HerdrCaretShellArgs.shellQuote(remotePath)}',
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
      cacheBase: base,
      remoteDir: remoteDir,
      tempPath: tempPath,
      remotePath: remotePath,
      timeout: timeout,
    );

    // 7. chmod 0700
    final chmodResult = await _sshRunner.exec(
      'chmod $remoteFileMode ${HerdrCaretShellArgs.shellQuote(remotePath)}',
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
    required String cacheBase,
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
      // SFTP mkdir is not recursive. Create the cache base and helper install
      // hierarchy in order, including when the cache base itself is absent.
      final cacheRoot = p.posix.normalize(cacheBase);
      final installRoot = p.posix.join(cacheRoot, remoteInstallDir);
      final parentRoot = p.posix.dirname(installRoot);
      await _sftpService.ensureDirectory(sftp, cacheRoot);
      await _sftpService.ensureDirectory(sftp, parentRoot);
      await _sftpService.ensureDirectory(sftp, installRoot);
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
    final sumResult = await _sshRunner.exec(
      'sha256sum ${HerdrCaretShellArgs.shellQuote(tempPath)}',
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
