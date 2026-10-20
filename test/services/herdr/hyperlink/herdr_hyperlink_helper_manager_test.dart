// inventory: HERDR-HYPERLINK-MANAGER-TEST-000
/// herdr_hyperlink_helper_manager.dart のテスト。
///
/// FakeSshClient で SSH コマンド列を記録・fixture 応答し、`hyperlinks`
/// サブコマンドの実行（引数・64KB 打ち切り・JSON 検証）と失敗分類を
/// 検証する。install 経路自体（sha256sum skip / upload / chmod）は caret の
/// `herdr_caret_helper_manager_test.dart` で検証済みのため、ここでは
/// skip 経路（既存ハッシュ一致）だけを使って manager 固有の差分に絞る。
///
/// protocol の値は生成物の定数（[kHerdrHyperlinkSupportedProtocols]）を
/// 参照する（allow-list の中身が変わってもテストを
/// 直す必要が無いようにする）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manifest.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_types.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_version.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_helper_manager.dart';
import 'package:flutter_muxpod/services/sftp/sftp_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_sftp_client.dart';
import '../../../helpers/fake_ssh_client.dart';

/// openSftp 呼び出しを計数する SshClient fake（skip 経路では 0 回のはず）。
class _CountingSshClient extends FakeSshClient {
  int openSftpCalls = 0;

  @override
  Future<SftpClient> openSftp() async {
    openSftpCalls++;
    return sftpClient;
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

/// 対応 protocol の1つ（allow-list の中身に依存しないよう先頭を使う）。
int get _supportedProtocol => kHerdrHyperlinkSupportedProtocols.first;

/// `hyperlinks` の出力形式どおりの fixture。
String _hyperlinkJson({
  String paneId = 'w1:p2',
  int? protocolVersion,
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
    [3, '9f1c000000000000'],
  ],
}) => jsonEncode({
  'paneId': paneId,
  'protocolVersion': protocolVersion ?? _supportedProtocol,
  'frameWidth': frameWidth,
  'frameHeight': frameHeight,
  'truncated': truncated,
  'links': links,
  'rowHashes': rowHashes,
});

class _Env {
  _Env() {
    ssh = _CountingSshClient();
    sftp = FakeSftpClient();
    ssh.sftpClient = sftp;
    manifest = _manifest();
    manager = HerdrHyperlinkHelperManager(
      ssh: ssh,
      manifest: manifest,
      binaryLoader: (assetPath) async => helperBytes,
      sftpService: SftpService(),
    );
  }

  late final _CountingSshClient ssh;
  late final FakeSftpClient sftp;
  late final HerdrCaretHelperManifest manifest;
  late final HerdrHyperlinkHelperManager manager;
  final String cacheBase = '/cache';

  String get remoteDir => '$cacheBase/mux-pod/herdr-caret/$helperSha';
  String get remotePath => '$remoteDir/herdr-caret-helper';

  /// install を skip 経路（既存ハッシュ一致）に固定し、`hyperlinks` 応答を
  /// 差し込む。
  void setUpLinux({String? hyperlinkOutput, int? hyperlinkExitCode}) {
    ssh.execOutputs['uname -s'] = 'Linux\n';
    ssh.execOutputs['uname -m'] = 'x86_64\n';
    ssh.execOutputs['XDG_CACHE_HOME'] = '$cacheBase\n';
    ssh.execOutputs['sha256sum'] = '$helperSha  $remotePath\n';
    ssh.execOutputs['hyperlinks'] = hyperlinkOutput ?? _hyperlinkJson();
    if (hyperlinkExitCode != null) {
      ssh.execExitCodes['hyperlinks'] = hyperlinkExitCode;
    }
  }

  HerdrStatus status({int? protocol, String? socket = '/tmp/herdr.sock'}) =>
      HerdrStatus(
        serverProtocol: protocol ?? _supportedProtocol,
        socket: socket,
      );

  Future<PaneHyperlinks> run({
    String paneId = 'w1:p2',
    int cols = 120,
    int rows = 40,
    HerdrStatus? status,
  }) => manager.run(
    status: status ?? this.status(),
    paneId: paneId,
    cols: cols,
    rows: rows,
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
    test('正常 JSON を PaneHyperlinks へ変換する（unmodifiable collections）', () async {
      final env = _Env()..setUpLinux();
      final result = await env.run();

      expect(result.frameWidth, 120);
      expect(result.frameHeight, 40);
      expect(result.truncated, isFalse);
      expect(result.links, hasLength(1));
      expect(result.links.single.url, 'https://example.com/');
      expect(result.links.single.ranges.single.row, 3);
      expect(result.links.single.ranges.single.startCol, 10);
      expect(result.links.single.ranges.single.endCol, 24);
      expect(result.rowFingerprints, {3: '9f1c000000000000'});

      expect(
        () => result.links.add(result.links.first),
        throwsUnsupportedError,
        reason: 'links は unmodifiable であること',
      );
      expect(
        () => result.links.single.ranges.add(result.links.single.ranges.first),
        throwsUnsupportedError,
        reason: 'ranges は unmodifiable であること',
      );
      expect(
        () => result.rowFingerprints[99] = 'x',
        throwsUnsupportedError,
        reason: 'rowFingerprints は unmodifiable であること',
      );

      // skip 経路（既存ハッシュ一致）では SFTP を開かない。
      expect(env.ssh.openSftpCalls, 0);
      expect(env.ssh.execCommands, anyElement(contains('hyperlinks')));
      expect(
        env.ssh.execCommands,
        anyElement(contains('--max-output-bytes \'60000\'')),
      );
    });

    test('hyperlinks の実行コマンドには --api-socket が渡る（helper が実 pty '
        'サイズを読めればそれを使い、読めなければ --cols/--rows へフォールバック）', () async {
      final env = _Env()..setUpLinux();
      await env.run();

      expect(
        env.ssh.execCommands,
        anyElement(contains("--api-socket '/tmp/herdr.sock'")),
      );
    });

    test('リンクが無い pane は空リストで返る', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: jsonEncode({
            'paneId': 'w1:p2',
            'protocolVersion': _supportedProtocol,
            'frameWidth': 80,
            'frameHeight': 24,
            'truncated': false,
            'links': [],
            'rowHashes': [],
          }),
        );
      final result = await env.run(cols: 80, rows: 24);
      expect(result.links, isEmpty);
      expect(result.rowFingerprints, isEmpty);
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

    test('不正な paneId は invalidOutput', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(paneId: 'w1:p\x01'),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('範囲外の cols/rows は invalidOutput', () async {
      final env = _Env()..setUpLinux();
      await expectLater(
        env.run(cols: -1),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });
  });

  group('run 失敗（helper 実行）', () {
    test('helper 非 0 終了は execFailed', () async {
      final env = _Env()..setUpLinux(hyperlinkExitCode: 1);
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.execFailed),
      );
    });
  });

  group('run 失敗（JSON 検証。型・寸法・範囲の境界）', () {
    test('JSON でない出力は invalidOutput', () async {
      final env = _Env()..setUpLinux(hyperlinkOutput: 'not json');
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('paneId 不一致は invalidOutput（誤応答・stale の検出）', () async {
      final env = _Env()
        ..setUpLinux(hyperlinkOutput: _hyperlinkJson(paneId: 'w2:p9'));
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('protocolVersion が要求した status.serverProtocol と不一致なら'
        ' invalidOutput（allow-list 内でも不一致は拒否）', () async {
      final mismatched = _supportedProtocol == 999 ? 998 : 999;
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(protocolVersion: mismatched),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('range の row が frameHeight 以上なら invalidOutput（境界チェック）', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            frameHeight: 40,
            links: const [
              {
                'url': 'https://example.com/',
                'ranges': [
                  [40, 0, 5],
                ],
              },
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('range の endCol が frameWidth 以上なら invalidOutput（境界チェック）', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            frameWidth: 120,
            links: const [
              {
                'url': 'https://example.com/',
                'ranges': [
                  [3, 0, 120],
                ],
              },
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('rowHashes の row が frameHeight 以上なら invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            frameHeight: 40,
            rowHashes: const [
              [40, '9f1c000000000000'],
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('rowHashes の hex が16桁小文字hex書式でなければ invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            rowHashes: const [
              [3, 'ABCD'],
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('links[].url が空文字列なら invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            links: const [
              {
                'url': '',
                'ranges': [
                  [3, 0, 5],
                ],
              },
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('rowHashes の row が重複していれば invalidOutput（'
        'Map 変換での黙った上書きを防ぐ）', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            rowHashes: const [
              [3, '9f1c000000000000'],
              [3, '03ab000000000000'],
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('range の startCol > endCol は invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            links: const [
              {
                'url': 'https://example.com/',
                'ranges': [
                  [3, 24, 10],
                ],
              },
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('links[].ranges が空配列なら invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            links: const [
              {'url': 'https://example.com/', 'ranges': <Object?>[]},
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('links[].url に制御文字（C0/DEL）を含むと invalidOutput（'
        'スキーム許可判定はしない）', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            links: const [
              {
                'url': 'https://example.com/\x07evil',
                'ranges': [
                  [3, 10, 24],
                ],
              },
            ],
          ),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });

    test('検証失敗の例外メッセージに stdout 本文・URL・socket path を含まない', () async {
      const secretUrl = 'https://secret.example.com/token=abc123';
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: _hyperlinkJson(
            links: const [
              {
                'url': '$secretUrl\x07',
                'ranges': [
                  [3, 10, 24],
                ],
              },
            ],
          ),
        );
      try {
        await env.run();
        fail('invalidOutput のはずが成功した');
      } on HerdrCaretHelperException catch (e) {
        expect(e.message, isNot(contains(secretUrl)));
        expect(e.message, isNot(contains('/tmp/herdr.sock')));
      }
    });

    test('truncated が bool でなければ invalidOutput', () async {
      final env = _Env()
        ..setUpLinux(
          hyperlinkOutput: jsonEncode({
            'paneId': 'w1:p2',
            'protocolVersion': _supportedProtocol,
            'frameWidth': 120,
            'frameHeight': 40,
            'truncated': 'yes',
            'links': [],
            'rowHashes': [],
          }),
        );
      await expectLater(
        env.run(),
        _failsWith(HerdrCaretHelperFailure.invalidOutput),
      );
    });
  });
}
