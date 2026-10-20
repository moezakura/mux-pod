// inventory: HERDR-CARET-EXEC-TEST-000
/// herdr_caret_helper_executor.dart のテスト（サブコマンド対応・
/// SSH実行timeoutとhelperの--timeout-ms分離・subcommand の
/// allow-list 化・追加フラグの executor 自身による quote）。
///
/// FakeSshClient にコマンド文字列を記録させ、caret（既存互換）・hyperlinks・
/// scrollback-links の3形の組み立てを直接検証する。
library;

import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_executor.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manifest.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_types.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_shell_args.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_ssh.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_ssh_client.dart';

const _manifest = HerdrCaretHelperManifest(
  version: 1,
  helperName: 'herdr-caret-helper',
  platforms: [],
);

const _installation = HerdrCaretInstallation(
  remotePath: '/cache/mux-pod/herdr-caret/abc/herdr-caret-helper',
  sha256: 'abc',
);

class _Env {
  _Env() {
    ssh = FakeSshClient();
    // すべての呼び出しに共通する `--pane` を fixture キーにする（caret /
    // hyperlinks / scrollback-links いずれのコマンドにも含まれる）。
    ssh.execOutputs['--pane'] = '{"ok":true}';
  }

  late final FakeSshClient ssh;

  HerdrCaretHelperExecutor get executor => HerdrCaretHelperExecutor(
    sshRunner: HerdrCaretSshRunner(ssh),
    manifest: _manifest,
  );

  String get lastCommand => ssh.execCommands.last;
}

void main() {
  group('caret 互換（subcommand 省略）', () {
    test('既存と同一のコマンド文字列を組み立てる', () async {
      final env = _Env();
      await env.executor.runHelper(
        _installation,
        clientSocket: '/tmp/herdr-client.sock',
        paneId: 'w1:p1',
        cols: 80,
        rows: 24,
        protocol: 17,
        timeout: const Duration(milliseconds: 1000),
      );
      expect(
        env.lastCommand,
        "${HerdrCaretShellArgs.shellQuote(_installation.remotePath)}"
        " --socket '/tmp/herdr-client.sock'"
        " --pane 'w1:p1'"
        ' --protocol 17'
        ' --cols 80'
        ' --rows 24'
        ' --timeout-ms 1000',
      );
    });
  });

  group('hyperlinks（subcommand 指定、rows 指定、postTimeoutArgs）', () {
    test('サブコマンド・--rows・--timeout-ms 後方の追加フラグを組み立てる', () async {
      final env = _Env();
      await env.executor.runHelper(
        _installation,
        subcommand: HerdrCaretHelperSubcommand.hyperlinks,
        clientSocket: '/tmp/herdr-client.sock',
        paneId: 'w1:p2',
        cols: 120,
        rows: 40,
        protocol: 22,
        timeout: const Duration(milliseconds: 1000),
        helperTimeout: const Duration(milliseconds: 1000),
        postTimeoutArgs: const [('--max-output-bytes', '60000')],
      );
      expect(
        env.lastCommand,
        "${HerdrCaretShellArgs.shellQuote(_installation.remotePath)}"
        ' hyperlinks'
        " --socket '/tmp/herdr-client.sock'"
        " --pane 'w1:p2'"
        ' --protocol 22'
        ' --cols 120'
        ' --rows 40'
        ' --timeout-ms 1000'
        " --max-output-bytes '60000'",
      );
    });
  });

  group(
    'scrollback-links（apiSocket・rows省略・preTimeoutArgs・postTimeoutArgs）',
    () {
      test('--api-socket が --socket より前に出て、--rows は出ない', () async {
        final env = _Env();
        await env.executor.runHelper(
          _installation,
          subcommand: HerdrCaretHelperSubcommand.scrollbackLinks,
          apiSocket: '/tmp/herdr.sock',
          clientSocket: '/tmp/herdr-client.sock',
          paneId: 'w1:p2',
          cols: 120,
          preTimeoutArgs: const [('--window', '120')],
          protocol: 22,
          timeout: const Duration(milliseconds: 3200),
          helperTimeout: const Duration(milliseconds: 1500),
          postTimeoutArgs: const [
            ('--restore-budget-ms', '700'),
            ('--max-output-bytes', '60000'),
          ],
        );
        expect(
          env.lastCommand,
          "${HerdrCaretShellArgs.shellQuote(_installation.remotePath)}"
          ' scrollback-links'
          " --api-socket '/tmp/herdr.sock'"
          " --socket '/tmp/herdr-client.sock'"
          " --pane 'w1:p2'"
          ' --protocol 22'
          ' --cols 120'
          " --window '120'"
          ' --timeout-ms 1500'
          " --restore-budget-ms '700'"
          " --max-output-bytes '60000'",
        );
      });

      test('--window を複数（最大3）渡せる', () async {
        final env = _Env();
        await env.executor.runHelper(
          _installation,
          subcommand: HerdrCaretHelperSubcommand.scrollbackLinks,
          apiSocket: '/tmp/herdr.sock',
          clientSocket: '/tmp/herdr-client.sock',
          paneId: 'w1:p2',
          cols: 120,
          preTimeoutArgs: const [
            ('--window', '120'),
            ('--window', '160'),
            ('--window', '200'),
          ],
          protocol: 22,
          timeout: const Duration(milliseconds: 3200),
        );
        expect(
          env.lastCommand,
          contains(
            " --window '120' --window '160' --window '200' --timeout-ms",
          ),
        );
      });
    },
  );

  group('helperTimeout の分離', () {
    test('helperTimeout 省略時は timeout と同値になる（既存互換）', () async {
      final env = _Env();
      await env.executor.runHelper(
        _installation,
        clientSocket: '/tmp/herdr-client.sock',
        paneId: 'w1:p1',
        cols: 80,
        rows: 24,
        protocol: 17,
        timeout: const Duration(milliseconds: 1000),
      );
      expect(env.lastCommand, contains('--timeout-ms 1000'));
    });

    test('helperTimeout を指定すると SSH exec の timeout とは独立する', () async {
      final env = _Env();
      await env.executor.runHelper(
        _installation,
        subcommand: HerdrCaretHelperSubcommand.scrollbackLinks,
        apiSocket: '/tmp/herdr.sock',
        clientSocket: '/tmp/herdr-client.sock',
        paneId: 'w1:p2',
        cols: 120,
        protocol: 22,
        // SSH exec 側の timeout（打ち切り猶予）は3200ms。
        timeout: const Duration(milliseconds: 3200),
        // helper の --timeout-ms は1500ms（取得用の予算）。
        helperTimeout: const Duration(milliseconds: 1500),
      );
      expect(env.lastCommand, contains('--timeout-ms 1500'));
      expect(env.lastCommand, isNot(contains('--timeout-ms 3200')));
    });
  });

  group('preTimeoutArgs / postTimeoutArgs の quote（executor が自身で行う）', () {
    test('空白・シングルクォート・; ・\$ を含む値が1引数として quote される', () async {
      final env = _Env();
      await env.executor.runHelper(
        _installation,
        subcommand: HerdrCaretHelperSubcommand.hyperlinks,
        clientSocket: '/tmp/herdr-client.sock',
        paneId: 'w1:p1',
        cols: 80,
        rows: 24,
        protocol: 17,
        timeout: const Duration(milliseconds: 1000),
        // 特殊文字を含む値でも、executor が shellQuote してから連結する。
        postTimeoutArgs: const [('--label', r"a b'c;d$e")],
      );
      expect(
        env.lastCommand,
        endsWith(
          "--timeout-ms 1000 --label ${HerdrCaretShellArgs.shellQuote(r"a b'c;d$e")}",
        ),
      );
      // quote されているため1個のシェル引数として渡る（分割されない）。
      expect(env.lastCommand, contains("--label 'a b'\\''c;d\$e'"));
    });

    test('不正なフラグ名（allow-list 外）は invalidOutput で拒否する', () async {
      final env = _Env();
      await expectLater(
        env.executor.runHelper(
          _installation,
          subcommand: HerdrCaretHelperSubcommand.hyperlinks,
          clientSocket: '/tmp/herdr-client.sock',
          paneId: 'w1:p1',
          cols: 80,
          rows: 24,
          protocol: 17,
          timeout: const Duration(milliseconds: 1000),
          // 先頭が `--` で始まらない・大文字を含む・空白を含む、のいずれも拒否。
          postTimeoutArgs: const [('label', 'x')],
        ),
        throwsA(
          isA<HerdrCaretHelperException>().having(
            (e) => e.failure,
            'failure',
            HerdrCaretHelperFailure.invalidOutput,
          ),
        ),
      );
    });

    test('既存 caret のコマンド文字列はバイト単位で不変（回帰）', () async {
      final env = _Env();
      await env.executor.runHelper(
        _installation,
        clientSocket: '/tmp/herdr-client.sock',
        paneId: 'w1:p1',
        cols: 80,
        rows: 24,
        protocol: 17,
        timeout: const Duration(milliseconds: 1000),
      );
      expect(
        env.lastCommand,
        "${HerdrCaretShellArgs.shellQuote(_installation.remotePath)}"
        " --socket '/tmp/herdr-client.sock'"
        " --pane 'w1:p1'"
        ' --protocol 17'
        ' --cols 80'
        ' --rows 24'
        ' --timeout-ms 1000',
      );
    });
  });

  group('helperErrorKind の抽出（herdr OSC 8 ハイパーリンク'
      '実験機能・非0終了時の stderr 分類）', () {
    Future<HerdrCaretHelperException> runAndCaptureFailure(
      _StderrInjectingSshClient ssh,
    ) async {
      final executor = HerdrCaretHelperExecutor(
        sshRunner: HerdrCaretSshRunner(ssh),
        manifest: _manifest,
      );
      try {
        await executor.runHelper(
          _installation,
          subcommand: HerdrCaretHelperSubcommand.scrollbackLinks,
          apiSocket: '/tmp/herdr.sock',
          clientSocket: '/tmp/herdr-client.sock',
          paneId: 'w1:p1',
          cols: 80,
          protocol: 22,
          timeout: const Duration(milliseconds: 3200),
          helperTimeout: const Duration(milliseconds: 1500),
        );
        fail('non-zero exit のはずが成功した');
      } on HerdrCaretHelperException catch (e) {
        return e;
      }
    }

    test('(a) busy の JSON から busy が取れる', () async {
      final ssh = _StderrInjectingSshClient(
        stderr: '{"error":"busy"}',
        exitCode: 1,
      );
      final e = await runAndCaptureFailure(ssh);
      expect(e.failure, HerdrCaretHelperFailure.execFailed);
      expect(e.helperErrorKind, HerdrHelperErrorKind.busy);
    });

    test('(a) winsize_unavailable の JSON から winsizeUnavailable が取れる'
        '（--api-socket 経由で実 pty サイズを読めなかった）', () async {
      final ssh = _StderrInjectingSshClient(
        stderr: '{"error":"winsize_unavailable"}',
        exitCode: 1,
      );
      final e = await runAndCaptureFailure(ssh);
      expect(e.failure, HerdrCaretHelperFailure.execFailed);
      expect(e.helperErrorKind, HerdrHelperErrorKind.winsizeUnavailable);
    });

    test('(b) 未知の kind は null になる', () async {
      final ssh = _StderrInjectingSshClient(
        stderr: '{"error":"totally_unknown_kind"}',
        exitCode: 1,
      );
      final e = await runAndCaptureFailure(ssh);
      expect(e.helperErrorKind, isNull);
    });

    test('(b) 非 JSON の stderr は null になる', () async {
      final ssh = _StderrInjectingSshClient(
        stderr: 'panic: something broke',
        exitCode: 1,
      );
      final e = await runAndCaptureFailure(ssh);
      expect(e.helperErrorKind, isNull);
    });

    test('(b) 256 バイトを超える stderr は null になる（内容も message へ出ない）', () async {
      final longKind = 'x' * 300;
      final ssh = _StderrInjectingSshClient(
        stderr: '{"error":"$longKind"}',
        exitCode: 1,
      );
      final e = await runAndCaptureFailure(ssh);
      expect(e.helperErrorKind, isNull);
      expect(e.message, isNot(contains(longKind)));
    });

    test('(b) error 以外のキーを含む JSON は null になる', () async {
      final ssh = _StderrInjectingSshClient(
        stderr: '{"error":"busy","extra":"x"}',
        exitCode: 1,
      );
      final e = await runAndCaptureFailure(ssh);
      expect(e.helperErrorKind, isNull);
    });
  });
}

/// [FakeSshClient.execWithExitCode] の戻り値に固定の stderr / exitCode を
/// 注入する（共有 test helper `fake_ssh_client.dart` には stderr 注入の口が
/// 無いため、このファイル内だけの subclass で対応する。既存ヘルパーは
/// 変更しない）。
class _StderrInjectingSshClient extends FakeSshClient {
  _StderrInjectingSshClient({required this.stderr, required this.exitCode}) {
    execOutputs['--pane'] = '{"ok":true}';
  }

  final String stderr;
  final int exitCode;

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    final base = await super.execWithExitCode(command, timeout: timeout);
    return (stdout: base.stdout, stderr: stderr, exitCode: exitCode);
  }
}
