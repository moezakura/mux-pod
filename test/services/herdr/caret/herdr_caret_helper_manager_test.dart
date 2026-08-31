// inventory: HERDR-CARET-MANAGER-TEST-000
/// herdr_caret_helper_manager.dart のテスト。
///
/// FakeSshClient で SSH コマンド列を記録・fixture 応答し、install（sha256sum
/// skip / upload / chmod）・helper 実行（shellQuote 引数・64KB 打ち切り・
/// JSON 検証）・失敗分類・install memo を検証する。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manager.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manifest.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/sftp/sftp_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_sftp_client.dart';
import '../../../helpers/fake_ssh_client.dart';

/// openSftp 呼び出しを計数し、失敗を注入できる SshClient fake。
class _CountingSshClient extends FakeSshClient {
  int openSftpCalls = 0;
  bool failOpenSftp = false;

  @override
  Future<SftpClient> openSftp() async {
    openSftpCalls++;
    if (failOpenSftp) throw StateError('sftp unavailable');
    return sftpClient;
  }
}

/// 特定パスの stat サイズを差し替えられる SFTP fake。
///
/// 実装は upload 後の一時ファイルを `sftp.stat(tempPath)` で検証するため、
/// リモート実ファイルと同じ size を返せるようにする。
class _StatAwareSftpClient extends FakeSftpClient {
  final Map<String, int> fileSizes = {};

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    final size = fileSizes[path];
    if (size != null) {
      return SftpFileAttrs(
        mode: SftpFileMode.value(0x81A4),
        size: size,
        modifyTime: DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000,
      );
    }
    return super.stat(path, followLink: followLink);
  }
}

Uint8List _helperBytes() =>
    Uint8List.fromList(List.generate(256, (i) => i & 0xFF));

late final Uint8List helperBytes;
late final String helperSha;

HerdrCaretHelperManifest _manifest() => HerdrCaretHelperManifest.fromJson(
  jsonEncode({
    'version': 1,
    'helperName': 'herdr-caret-helper',
    'platforms': [
      {
        'id': 'linux-x86_64',
        'os': 'linux',
        'arch': 'x86_64',
        'asset': 'assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper',
        'size': helperBytes.length,
        'sha256': helperSha,
      },
    ],
  }),
);

/// helper が返す単一 JSON 行の fixture。
String _helperJson({String paneId = 'w1:p1'}) =>
    '{"cursor":{"x":10,"y":4,"visible":true,"shape":0},'
    '"frameWidth":80,"frameHeight":24,"protocolVersion":17,'
    '"paneId":"$paneId"}';

class _Env {
  _Env({HerdrCaretBinaryLoader? loader}) {
    ssh = _CountingSshClient();
    sftp = _StatAwareSftpClient();
    ssh.sftpClient = sftp;
    manifest = _manifest();
    manager = HerdrCaretHelperManager(
      ssh: ssh,
      manifest: manifest,
      binaryLoader:
          loader ??
          (assetPath) async {
            loadedAssets.add(assetPath);
            return helperBytes;
          },
      sftpService: SftpService(),
    );
  }

  late final _CountingSshClient ssh;
  late final _StatAwareSftpClient sftp;
  late final HerdrCaretHelperManifest manifest;
  late final HerdrCaretHelperManager manager;
  final List<String> loadedAssets = [];
  final String cacheBase = '/cache';

  String get remoteDir => '$cacheBase/mux-pod/herdr-caret/$helperSha';
  String get remotePath => '$remoteDir/herdr-caret-helper';
  String get tempPath => '$remoteDir/.herdr-caret-helper.tmp';

  /// 標準 fixture: Linux x86_64・既存 helper の sha256 一致（upload skip）。
  void setUpLinux() {
    ssh.execOutputs['uname -s'] = 'Linux\n';
    ssh.execOutputs['uname -m'] = 'x86_64\n';
    ssh.execOutputs['XDG_CACHE_HOME'] = '$cacheBase\n';
    ssh.execOutputs['sha256sum'] = '$helperSha  $remotePath\n';
    ssh.execOutputs['--pane'] = _helperJson();
  }

  /// fixture: sha256sum 不一致（exit 1）→ upload → rename → chmod 経路。
  ///
  /// FakeSshClient は最初にマッチした fixture を使うため、一時ファイルの
  /// 検証コマンドを作業対象の sha256sum より先に挿入する（優先順位）。
  void setUpInstall() {
    ssh.execOutputs['uname -s'] = 'Linux\n';
    ssh.execOutputs['uname -m'] = 'x86_64\n';
    ssh.execOutputs['XDG_CACHE_HOME'] = '$cacheBase\n';
    ssh.execOutputs['.herdr-caret-helper.tmp'] = '$helperSha  $tempPath\n';
    ssh.execOutputs['sha256sum'] = '';
    ssh.execOutputs['--pane'] = _helperJson();
    ssh.execExitCodes['.herdr-caret-helper.tmp'] = 0;
    ssh.execExitCodes['sha256sum'] = 1;
    sftp.fileSizes[tempPath] = helperBytes.length;
  }

  HerdrStatus status({int protocol = 17, String? socket = '/tmp/herdr.sock'}) =>
      HerdrStatus(serverProtocol: protocol, socket: socket);

  Future<HerdrCaretHelperRunResult> run({
    String paneId = 'w1:p1',
    int cols = 80,
    int rows = 24,
    HerdrStatus? status,
  }) => manager.run(
    status: status ?? this.status(),
    paneId: paneId,
    cols: cols,
    rows: rows,
  );
}

/// [future] が指定の失敗分類で失敗することを検証する。
Matcher _failsWith(HerdrCaretHelperFailure failure) => throwsA(
  isA<HerdrCaretHelperException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  setUpAll(() {
    helperBytes = _helperBytes();
    helperSha = hexSha256(helperBytes);
  });

  group('deriveClientSocket', () {
    test('herdr.sock → herdr-client.sock を導出する', () {
      expect(
        HerdrCaretHelperManager.deriveClientSocket('herdr.sock'),
        'herdr-client.sock',
      );
      expect(
        HerdrCaretHelperManager.deriveClientSocket('/tmp/x.sock'),
        '/tmp/x-client.sock',
      );
      expect(
        HerdrCaretHelperManager.deriveClientSocket('/run/user/1000/herdr.sock'),
        '/run/user/1000/herdr-client.sock',
      );
    });
  });

  group('isValidPaneId / shellQuote', () {
    test('isValidPaneId は 1..64 文字・印字可能 ASCII のみ許可する', () {
      expect(HerdrCaretHelperManager.isValidPaneId('w1:p1'), isTrue);
      expect(HerdrCaretHelperManager.isValidPaneId(''), isFalse);
      expect(HerdrCaretHelperManager.isValidPaneId('a' * 65), isFalse);
      expect(HerdrCaretHelperManager.isValidPaneId('w1:p\x01'), isFalse);
    });

    test('shellQuote は single quote を POSIX 形式でエスケープする', () {
      expect(HerdrCaretHelperManager.shellQuote('plain'), "'plain'");
      expect(
        HerdrCaretHelperManager.shellQuote(r"w1:p1'o'"),
        r"'w1:p1'\''o'\'''",
      );
      expect(
        HerdrCaretHelperManager.shellQuote('a b'),
        "'a b'",
      );
    });
  });

  group('run 成功（sha256sum skip 経路）', () {
    test('uname → cache base → sha256sum → helper 実行が順に流れる', () async {
      final env = _Env()..setUpLinux();
      final result = await env.run();
      expect(result.remotePath, env.remotePath);
      expect(result.stdout, _helperJson());
      final cmds = env.ssh.execCommands;
      expect(cmds, contains('uname -s'));
      expect(cmds, contains('uname -m'));
      // m1 修正後の形式: フォーマット部がクォートされていること
      // （非クォートだとシェルのエスケープ除去で末尾に `n` が付加され
      // cache base が ~/.cachen になってしまう回帰検証）。
      expect(
        cmds,
        anyElement("printf '%s\\n' \"\${XDG_CACHE_HOME:-\$HOME/.cache}\""),
      );
      expect(cmds, anyElement(startsWith('sha256sum ')));
      expect(cmds, anyElement(contains('--pane ')));
      // skip 経路では SFTP を開かず chmod も実行しない
      expect(env.ssh.openSftpCalls, 0);
      expect(cmds.any((c) => c.startsWith('chmod ')), isFalse);
    });

    test('XDG_CACHE_HOME の内容を配置先パスへ反映する', () async {
      final env = _Env()..setUpLinux();
      final result = await env.run();
      expect(
        result.remotePath,
        '/cache/mux-pod/herdr-caret/$helperSha/herdr-caret-helper',
      );
    });

    test('helper 実行コマンドが shellQuote 済み引数で組み立てられる', () async {
      final env = _Env()..setUpLinux();
      await env.run(paneId: r"w1:p1'o'", cols: 100, rows: 30);
      final helperCmd = env.ssh.execCommands.firstWhere((c) => c.contains('--pane '));
      expect(helperCmd, contains("--socket '/tmp/herdr-client.sock'"));
      expect(
        helperCmd,
        contains('--pane ${HerdrCaretHelperManager.shellQuote(r"w1:p1'o'")}'),
      );
      expect(helperCmd, contains('--protocol 17'));
      expect(helperCmd, contains('--cols 100'));
      expect(helperCmd, contains('--rows 30'));
      expect(helperCmd, contains('--timeout-ms 1000'));
    });

    test('install memo: 同一 SshClient では 2 回目の run で uname を再実行しない', () async {
      final env = _Env()..setUpLinux();
      await env.run(paneId: 'w1:p1');
      await env.run(paneId: 'w1:p2');
      expect(env.ssh.execCommands.where((c) => c == 'uname -s'), hasLength(1));
      expect(env.ssh.execCommands.where((c) => c == 'uname -m'), hasLength(1));
      expect(env.ssh.execCommands.where((c) => c.contains('--pane ')), hasLength(2));
      expect(env.ssh.openSftpCalls, 0);
      // helper 実行は memo されず毎回実行される（実行頻度は reader 側の契約）
      expect(env.loadedAssets, hasLength(1));
    });
  });

  group('install（upload 経路）', () {
    test('sha256sum 不一致なら upload → 検証 → rename → chmod 0700 する', () async {
      final env = _Env()..setUpInstall();
      final result = await env.run();
      expect(result.remotePath, env.remotePath);
      expect(env.ssh.openSftpCalls, 1);
      // upload されたバイト列が bundle fixture と一致する
      expect(env.sftp.openedFiles, hasLength(1));
      expect(env.sftp.openedFiles.single.content.length, helperBytes.length);
      // upload 後の sha256 再検証が一時ファイルに対して走る
      expect(env.ssh.execCommands, contains("sha256sum '${env.tempPath}'"));
      // 検証成功後に rename、続いて chmod 0700
      expect(env.sftp.renameCalls, [(env.tempPath, env.remotePath)]);
      final chmod = env.ssh.execCommands.firstWhere((c) => c.startsWith('chmod '));
      expect(chmod, "chmod 0700 '${env.remotePath}'");
    });

    test('install memo: 2 回目の run では upload を再実行しない', () async {
      final env = _Env()..setUpInstall();
      await env.run();
      await env.run();
      expect(env.ssh.execCommands.where((c) => c == 'uname -s'), hasLength(1));
      expect(env.ssh.openSftpCalls, 1);
      expect(env.ssh.execCommands.where((c) => c.contains('--pane ')), hasLength(2));
    });

    test('chmod が非ゼロ終了なら execFailed', () async {
      final env = _Env()..setUpInstall();
      env.ssh.execExitCodes['chmod'] = 1;
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.execFailed));
    });
  });

  group('helper 出力の検証', () {
    test('JSON でない出力は invalidOutput で拒否する', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execOutputs['--pane'] = 'hello world';
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.invalidOutput));
    });

    test('出力が 64KB を超える場合は打ち切って返す', () async {
      final env = _Env()..setUpLinux();
      final head =
          '{"cursor":null,"frameWidth":80,"frameHeight":24,'
          '"protocolVersion":17,"paneId":"w1:p1"}';
      // 先頭 64KB の末尾が '}' になるようパディングし、総長は 64KB 超にする
      final n = HerdrCaretHelperManager.maxStdoutBytes - 1 - head.length;
      final long = '$head${'A' * n}}B';
      expect(long.length, greaterThan(HerdrCaretHelperManager.maxStdoutBytes));
      env.ssh.execOutputs['--pane'] = long;
      final result = await env.run();
      expect(result.stdout.length, HerdrCaretHelperManager.maxStdoutBytes);
      expect(result.stdout.endsWith('}'), isTrue);
    });

    test('helper が空出力（exit 0）なら invalidOutput で拒否する', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execOutputs['--pane'] = '';
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.invalidOutput));
    });
  });

  group('失敗分類', () {
    test('unsupportedProtocol: protocol 18 では実行前に失敗する', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(status: env.status(protocol: 18)),
        _failsWith(HerdrCaretHelperFailure.unsupportedProtocol),
      );
      expect(env.ssh.execCommands, isEmpty);
    });

    test('unsupported: API socket が無ければ失敗する', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(status: env.status(socket: null)),
        _failsWith(HerdrCaretHelperFailure.unsupported),
      );
      expect(env.ssh.execCommands, isEmpty);
    });

    test('unsupported: Darwin（非 Linux）は失敗する', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execOutputs['uname -s'] = 'Darwin\n';
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.unsupported));
    });

    test('unsupported: 未知 arch は失敗する', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execOutputs['uname -m'] = 'mips64\n';
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.unsupported));
    });

    test('invalidOutput: pane ID の書式不正は実行前に失敗する', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(paneId: ''),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
      expect(env.ssh.execCommands, isEmpty);
    });

    test('connectFailed: uname -s が非ゼロ終了', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execExitCodes['uname -s'] = 1;
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.connectFailed));
    });

    test('connectFailed: uname -m の出力が空', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execOutputs['uname -m'] = '';
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.connectFailed));
    });

    test('hashMismatch: bundle のバイト列が manifest と不一致', () async {
      final env =
          _Env(loader: (_) async => Uint8List.fromList([9, 9, 9, 9]))
            ..setUpLinux();
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.hashMismatch));
    });

    test('uploadFailed: SFTP セッションが開けない', () async {
      final env = _Env()..setUpInstall();
      env.ssh.failOpenSftp = true;
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.uploadFailed));
    });

    test('hashMismatch: upload 後の sha256/size 再検証が不一致', () async {
      final env = _Env()..setUpInstall();
      env.ssh.execOutputs['.herdr-caret-helper.tmp'] = '0' * 64;
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.hashMismatch));
      // 不一致時は一時ファイルを削除する
      expect(env.sftp.removeCalls, [env.tempPath]);
    });

    test('execFailed: helper が非ゼロ終了', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execExitCodes['--pane'] = 1;
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.execFailed));
    });

    test('timeout: helper 実行がタイムアウト', () async {
      final env = _Env()..setUpLinux();
      env.ssh.execExceptions['--pane'] = TimeoutException('timed out');
      await expectLater(env.run(), _failsWith(HerdrCaretHelperFailure.timeout));
    });
  });
}