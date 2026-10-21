/// herdr_scrollback_link_helper_manager.dart のテスト。
///
/// install 経路自体は caret の `herdr_caret_helper_manager_test.dart` で
/// 検証済みのため、ここでは skip 経路（既存ハッシュ一致）だけを使って
/// manager 固有の差分（引数構築・JSON 検証）に絞る。protocol の値は生成物
/// の定数（[kHerdrScrollbackLinkSupportedProtocols]）を参照する。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manifest.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_types.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_version.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import 'package:flutter_muxpod/services/sftp/sftp_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_sftp_client.dart';
import '../../../helpers/fake_ssh_client.dart';

class _CountingSshClient extends FakeSshClient {
  int openSftpCalls = 0;

  /// 非0終了時に返す stderr（既定は空。busy 抽出テストでのみ差し替える）。
  String stderrOverride = '';

  @override
  Future<SftpClient> openSftp() async {
    openSftpCalls++;
    return sftpClient;
  }

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    final base = await super.execWithExitCode(command, timeout: timeout);
    if (stderrOverride.isEmpty) return base;
    return (
      stdout: base.stdout,
      stderr: stderrOverride,
      exitCode: base.exitCode,
    );
  }
}

Uint8List _helperBytes([int seed = 0]) =>
    Uint8List.fromList(List.generate(256, (i) => (i + seed) & 0xFF));

late final Uint8List helperBytes;
late final String helperSha;

HerdrCaretHelperManifest _manifest([Uint8List? bytes, String? sha]) =>
    HerdrCaretHelperManifest.fromJson(
      jsonEncode({
        'version': 1,
        'helperName': 'herdr-caret-helper',
        'platforms': [
          {
            'id': 'linux-x86_64',
            'os': 'linux',
            'arch': 'x86_64',
            'asset':
                'assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper',
            'size': (bytes ?? helperBytes).length,
            'sha256': sha ?? helperSha,
          },
        ],
      }),
    );

/// 対応 protocol の1つ（allow-list の中身に依存しないよう先頭を使う）。
int get _supportedProtocol => kHerdrScrollbackLinkSupportedProtocols.first;

Map<String, Object?> _window({
  int requestedOffset = 120,
  int actualOffset = 120,
  int frameWidth = 120,
  int frameHeight = 40,
  bool truncated = false,
  List<Map<String, Object?>> links = const [
    {
      'url': 'https://example.com/',
      'ranges': [
        [3, 10, 24],
      ],
    },
  ],
  List<List<Object?>> rowHashes = const [
    [0, '9f1c000000000000'],
  ],
}) => {
  'requestedOffset': requestedOffset,
  'actualOffset': actualOffset,
  'frameWidth': frameWidth,
  'frameHeight': frameHeight,
  'truncated': truncated,
  'links': links,
  'rowHashes': rowHashes,
};

/// `scrollback-links` の出力形式どおりの fixture。
String _scrollbackLinksJson({
  String paneId = 'w1:p2',
  int? protocolVersion,
  String restore = 'exact',
  List<Map<String, Object?>>? windows,
}) => jsonEncode({
  'paneId': paneId,
  'protocolVersion': protocolVersion ?? _supportedProtocol,
  'restore': restore,
  'windows': windows ?? [_window()],
});

class _Env {
  _Env({Uint8List? helperBytesOverride, String? helperShaOverride})
    : _bytes = helperBytesOverride ?? helperBytes,
      sha = helperShaOverride ?? helperSha {
    ssh = _CountingSshClient();
    sftp = FakeSftpClient();
    ssh.sftpClient = sftp;
    manifest = _manifest(_bytes, sha);
    manager = HerdrScrollbackLinkHelperManager(
      ssh: ssh,
      manifest: manifest,
      binaryLoader: (assetPath) async => _bytes,
      sftpService: SftpService(),
    );
  }

  final Uint8List _bytes;

  /// この env が使う helper の sha256（既定はグローバル [helperSha]。
  /// バージョン別 lock-dir テストでは別の値を渡す）。
  final String sha;

  late final _CountingSshClient ssh;
  late final FakeSftpClient sftp;
  late final HerdrCaretHelperManifest manifest;
  late final HerdrScrollbackLinkHelperManager manager;
  final String cacheBase = '/cache';

  String get remoteDir => '$cacheBase/mux-pod/herdr-caret/$sha';
  String get remotePath => '$remoteDir/herdr-caret-helper';

  void setUpLinux({String? output, int? exitCode}) {
    ssh.execOutputs['uname -s'] = 'Linux\n';
    ssh.execOutputs['uname -m'] = 'x86_64\n';
    ssh.execOutputs['XDG_CACHE_HOME'] = '$cacheBase\n';
    ssh.execOutputs['sha256sum'] = '$sha  $remotePath\n';
    ssh.execOutputs['scrollback-links'] = output ?? _scrollbackLinksJson();
    if (exitCode != null) {
      ssh.execExitCodes['scrollback-links'] = exitCode;
    }
  }

  HerdrStatus status({int? protocol, String? socket = '/tmp/herdr.sock'}) =>
      HerdrStatus(
        serverProtocol: protocol ?? _supportedProtocol,
        socket: socket,
      );

  Future<ScrollbackLinksResult> run({
    String paneId = 'w1:p2',
    int cols = 120,
    List<int> offsetsFromBottom = const [120],
    HerdrStatus? status,
  }) => manager.run(
    status: status ?? this.status(),
    paneId: paneId,
    cols: cols,
    offsetsFromBottom: offsetsFromBottom,
  );
}

Matcher _failsWith(HerdrCaretHelperFailure failure) => throwsA(
  isA<HerdrCaretHelperException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  setUpAll(() {
    helperBytes = _helperBytes();
    helperSha = hexSha256(helperBytes);
  });

  group('run 成功', () {
    test('正常 JSON を ScrollbackLinksResult へ変換する', () async {
      final env = _Env()..setUpLinux();
      final result = await env.run();

      expect(result.restore, ScrollbackLinkRestore.exact);
      expect(result.windows, hasLength(1));
      final window = result.windows.single;
      expect(window.requestedOffset, 120);
      expect(window.actualOffset, 120);
      expect(window.hyperlinks.frameWidth, 120);
      expect(window.hyperlinks.frameHeight, 40);
      expect(window.hyperlinks.links.single.url, 'https://example.com/');
      expect(window.hyperlinks.rowFingerprints, {0: '9f1c000000000000'});

      expect(
        () => result.windows.add(result.windows.first),
        throwsUnsupportedError,
      );

      // skip 経路（既存ハッシュ一致）では SFTP を開かない。
      expect(env.ssh.openSftpCalls, 0);
      final cmd = env.ssh.execCommands.firstWhere(
        (c) => c.contains('scrollback-links'),
      );
      expect(cmd, contains('--api-socket'));
      expect(cmd, contains("--window '120'"));
      expect(cmd, contains("--restore-budget-ms '700'"));
      expect(cmd, contains("--max-output-bytes '60000'"));
      // lock-dir は sha256 ディレクトリの親。
      expect(
        cmd,
        contains("--lock-dir '${env.cacheBase}/mux-pod/herdr-caret/locks'"),
      );
      expect(cmd, isNot(contains('--rows')));
    });

    test('異なる sha256（remotePath）でも同じ --lock-dir が渡る'
        '（バージョン違いの端末間でも同じ pane への排他が効くこと）', () async {
      final envA = _Env()..setUpLinux();
      final envB = _Env(
        helperBytesOverride: _helperBytes(1),
        helperShaOverride: hexSha256(_helperBytes(1)),
      )..setUpLinux();

      await envA.run();
      await envB.run();

      String lockDirArgOf(_Env env) {
        final cmd = env.ssh.execCommands.firstWhere(
          (c) => c.contains('scrollback-links'),
        );
        final match = RegExp(r"--lock-dir '([^']*)'").firstMatch(cmd);
        expect(match, isNotNull, reason: '--lock-dir が見つからない: $cmd');
        return match!.group(1)!;
      }

      expect(envA.remotePath, isNot(envB.remotePath));
      expect(lockDirArgOf(envA), lockDirArgOf(envB));
      expect(lockDirArgOf(envA), '${envA.cacheBase}/mux-pod/herdr-caret/locks');
    });

    test('複数窓（--window 最大3）を要求順に照合する', () async {
      final env = _Env()
        ..setUpLinux(
          output: _scrollbackLinksJson(
            windows: [
              _window(requestedOffset: 0, actualOffset: 0),
              _window(requestedOffset: 60, actualOffset: 60),
              _window(requestedOffset: 120, actualOffset: 118),
            ],
          ),
        );
      final result = await env.run(offsetsFromBottom: const [0, 60, 120]);
      expect(result.windows, hasLength(3));
      expect(result.windows.map((w) => w.requestedOffset), [0, 60, 120]);

      final cmd = env.ssh.execCommands.firstWhere(
        (c) => c.contains('scrollback-links'),
      );
      expect(cmd, contains("--window '0' --window '60' --window '120'"));
    });
  });

  group('run 失敗（前提条件）', () {
    test('allow-list 外の protocol は unsupportedProtocol', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(status: env.status(protocol: 999)),
        _failsWith(HerdrCaretHelperFailure.unsupportedProtocol),
      );
    });

    test('API socket が無ければ unsupported', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(status: env.status(socket: null)),
        _failsWith(HerdrCaretHelperFailure.unsupported),
      );
    });

    test('offsetsFromBottom が空なら invalidOutput', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(offsetsFromBottom: const []),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('offsetsFromBottom が4個以上なら invalidOutput', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(offsetsFromBottom: const [0, 1, 2, 3]),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });
  });

  group('run 失敗（helper 実行）', () {
    test('helper 非 0 終了は execFailed', () async {
      final env = _Env()..setUpLinux(exitCode: 1);
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.execFailed),
      );
    });

    test('stderr が {"error":"busy"} なら helperErrorKind が busy になる'
        '（executor の busy 抽出自体は herdr_caret_helper_executor_test.dart'
        ' で検証済みだが、manager が透過することをここで確認する）', () async {
      final env = _Env()
        ..setUpLinux(exitCode: 1)
        ..ssh.stderrOverride = '{"error":"busy"}';
      try {
        await env.run();
        fail('non-zero exit のはずが成功した');
      } on HerdrCaretHelperException catch (e) {
        expect(e.failure, HerdrCaretHelperFailure.execFailed);
        expect(e.helperErrorKind, HerdrHelperErrorKind.busy);
      }
    });
  });

  group('run 失敗（JSON 検証）', () {
    test('paneId 不一致は invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(output: _scrollbackLinksJson(paneId: 'w2:p9'));
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('protocolVersion 不一致は invalidOutput', () async {
      final mismatched = _supportedProtocol == 999 ? 998 : 999;
      final env = _Env()
        ..setUpLinux(output: _scrollbackLinksJson(protocolVersion: mismatched));
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('restore が4値以外なら invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(output: _scrollbackLinksJson(restore: 'weird'));
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('windows の数が要求数と不一致なら invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          output: _scrollbackLinksJson(
            windows: [
              _window(requestedOffset: 120),
              _window(requestedOffset: 60),
            ],
          ),
        );
      await expectLater(
        env.run(offsetsFromBottom: const [120]),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('requestedOffset が要求順・値と不一致なら invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          output: _scrollbackLinksJson(windows: [_window(requestedOffset: 60)]),
        );
      await expectLater(
        env.run(offsetsFromBottom: const [120]),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('actualOffset が負なら invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          output: _scrollbackLinksJson(windows: [_window(actualOffset: -1)]),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('窓内の rowHashes 重複は invalidOutput（hyperlinks と同じ検証）', () async {
      final env = _Env()
        ..setUpLinux(
          output: _scrollbackLinksJson(
            windows: [
              _window(
                rowHashes: const [
                  [0, '9f1c000000000000'],
                  [0, '03ab000000000000'],
                ],
              ),
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('窓内の links[].url の制御文字は invalidOutput（hyperlinks と同じ検証）', () async {
      final env = _Env()
        ..setUpLinux(
          output: _scrollbackLinksJson(
            windows: [
              _window(
                links: const [
                  {
                    'url': 'https://example.com/\x07evil',
                    'ranges': [
                      [3, 10, 24],
                    ],
                  },
                ],
              ),
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });
  });
}
