// inventory: HERDR-CARET-MANIFEST-TEST-000
/// herdr_caret_helper_manifest.dart の単体テスト。
///
/// fromJson（正常・破損・version 不一致・空 platforms）、selectFor
/// （Linux x86_64/aarch64 当たり・amd64/arm64 正規化・非 Linux/未知 arch は
/// null）、matchesBytes（size/sha256 一致・不一致）、hexSha256 を検証する。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// テスト用 fixture バイト列（sha256 は manifest と連動させる）。
Uint8List _helperBytes() => Uint8List.fromList([1, 2, 3, 4]);

/// 標準 manifest（linux-x86_64 と linux-aarch64 の 2 platform）。
HerdrCaretHelperManifest _manifest({List<Map<String, dynamic>>? platforms}) {
  final bytes = _helperBytes();
  return HerdrCaretHelperManifest.fromJson(
    jsonEncode({
      'version': 1,
      'helperName': 'herdr-caret-helper',
      'platforms':
          platforms ??
          [
            {
              'id': 'linux-x86_64',
              'os': 'linux',
              'arch': 'x86_64',
              'asset':
                  'assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper',
              'size': bytes.length,
              'sha256': hexSha256(bytes),
            },
            {
              'id': 'linux-aarch64',
              'os': 'linux',
              'arch': 'aarch64',
              'asset':
                  'assets/herdr-caret-helper/linux-aarch64/herdr-caret-helper',
              'size': bytes.length,
              'sha256': hexSha256(bytes),
            },
          ],
    }),
  );
}

Map<String, dynamic> _platform({
  String id = 'linux-x86_64',
  String os = 'linux',
  String arch = 'x86_64',
  String asset = 'assets/helper',
}) {
  final bytes = _helperBytes();
  return {
    'id': id,
    'os': os,
    'arch': arch,
    'asset': asset,
    'size': bytes.length,
    'sha256': hexSha256(bytes),
  };
}

void main() {
  group('fromJson', () {
    test('正常な manifest をパースする', () {
      final manifest = _manifest();
      expect(manifest.version, 1);
      expect(manifest.helperName, 'herdr-caret-helper');
      expect(manifest.platforms, hasLength(2));
      final x86 = manifest.platforms[0];
      expect(x86.id, 'linux-x86_64');
      expect(x86.os, 'linux');
      expect(x86.arch, 'x86_64');
      expect(
        x86.asset,
        'assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper',
      );
      expect(x86.size, _helperBytes().length);
      expect(x86.sha256, hexSha256(_helperBytes()));
    });

    test('破損 JSON は FormatException', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson('{ not json'),
        throwsFormatException,
      );
    });

    test('JSON object でないものは FormatException', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson('[1, 2, 3]'),
        throwsFormatException,
      );
    });

    test('version が int でないものは FormatException', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({
            'version': 'one',
            'helperName': 'x',
            'platforms': [_platform()],
          }),
        ),
        throwsFormatException,
      );
    });

    test('version 不一致は FormatException（メッセージに期待 version を含む）', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({
            'version': 2,
            'helperName': 'x',
            'platforms': [_platform()],
          }),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('expected $kHerdrCaretHelperManifestVersion'),
          ),
        ),
      );
    });

    test('helperName が空・欠落は FormatException', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({
            'version': 1,
            'helperName': '',
            'platforms': [_platform()],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({
            'version': 1,
            'platforms': [_platform()],
          }),
        ),
        throwsFormatException,
      );
    });

    test('platforms が空リストは FormatException', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({
            'version': 1,
            'helperName': 'x',
            'platforms': <Object>[],
          }),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no platforms'),
          ),
        ),
      );
    });

    test('platforms が欠落・非リストは FormatException', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({'version': 1, 'helperName': 'x'}),
        ),
        throwsFormatException,
      );
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({
            'version': 1,
            'helperName': 'x',
            'platforms': 'not-a-list',
          }),
        ),
        throwsFormatException,
      );
    });

    test('platform エントリの必須フィールド欠落は FormatException', () {
      expect(
        () => HerdrCaretHelperManifest.fromJson(
          jsonEncode({
            'version': 1,
            'helperName': 'x',
            'platforms': [
              {
                'id': 'linux-x86_64',
                'os': 'linux',
                'arch': 'x86_64',
                'asset': 'a',
                'size': 4,
              },
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('selectFor', () {
    final manifest = _manifest();

    test('Linux / x86_64 は linux-x86_64 に当たる', () {
      expect(manifest.selectFor('Linux', 'x86_64')?.id, 'linux-x86_64');
      expect(manifest.selectFor('linux', 'x86_64')?.id, 'linux-x86_64');
    });

    test('Linux / aarch64 は linux-aarch64 に当たる', () {
      expect(manifest.selectFor('Linux', 'aarch64')?.id, 'linux-aarch64');
    });

    test('amd64 は x86_64 に正規化される', () {
      expect(manifest.selectFor('linux', 'amd64')?.id, 'linux-x86_64');
    });

    test('arm64 は aarch64 に正規化される', () {
      expect(manifest.selectFor('linux', 'arm64')?.id, 'linux-aarch64');
    });

    test('Darwin（非 Linux）は null', () {
      expect(manifest.selectFor('Darwin', 'x86_64'), isNull);
      expect(manifest.selectFor('darwin', 'arm64'), isNull);
    });

    test('未知 arch は null', () {
      expect(manifest.selectFor('linux', 'mips64'), isNull);
    });

    test('manifest に無い組合せ（linux / i386）は null', () {
      expect(manifest.selectFor('linux', 'i386'), isNull);
    });
  });

  group('matchesBytes', () {
    test('size と sha256 が一致すれば true', () {
      expect(_x86Platform().matchesBytes(_helperBytes()), isTrue);
    });

    test('size 不一致は false', () {
      final platform = _x86Platform();
      final wrongSize = Uint8List.fromList([1, 2, 3]);
      expect(platform.matchesBytes(wrongSize), isFalse);
    });

    test('sha256 不一致は false（size は一致）', () {
      final platform = _x86Platform();
      final wrongBytes = Uint8List.fromList([1, 2, 3, 5]);
      expect(platform.matchesBytes(wrongBytes), isFalse);
    });

    test('manifest の sha256 が大文字 hex でも一致する', () {
      final bytes = _helperBytes();
      final platform = HerdrCaretHelperPlatform(
        id: 'linux-x86_64',
        os: 'linux',
        arch: 'x86_64',
        asset: 'assets/helper',
        size: bytes.length,
        sha256: hexSha256(bytes).toUpperCase(),
      );
      expect(platform.matchesBytes(bytes), isTrue);
    });
  });

  group('hexSha256', () {
    test('小文字 hex 64 文字を返す', () {
      final digest = hexSha256(utf8.encode('abc'));
      expect(
        digest,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}

/// linux-x86_64 platform を返す（matchesBytes 用）。
HerdrCaretHelperPlatform _x86Platform() {
  final bytes = _helperBytes();
  return HerdrCaretHelperPlatform(
    id: 'linux-x86_64',
    os: 'linux',
    arch: 'x86_64',
    asset: 'assets/helper',
    size: bytes.length,
    sha256: hexSha256(bytes),
  );
}
