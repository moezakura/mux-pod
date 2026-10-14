import 'package:flutter_muxpod/features/updater/release_info.dart';
import 'package:flutter_muxpod/features/updater/update_failure.dart';
import 'package:flutter_muxpod/features/updater/update_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = UpdateSource(
  repo: 'moezakura/mux-pod',
  apkAssetName: 'app-release.apk',
);

Map<String, dynamic> _release({
  String tag = 'v0.3.0',
  List<Map<String, dynamic>>? assets,
}) => {
  'tag_name': tag,
  'body': '## Changes',
  'html_url': 'https://github.com/moezakura/mux-pod/releases/tag/$tag',
  'published_at': '2026-10-01T00:00:00Z',
  'assets':
      assets ??
      [
        {
          'name': 'app-release.apk',
          'size': 1234,
          'browser_download_url':
              'https://github.com/moezakura/mux-pod/releases/download/$tag/app-release.apk',
        },
        {
          'name': 'app-release.apk.sha256',
          'size': 82,
          'browser_download_url':
              'https://github.com/moezakura/mux-pod/releases/download/$tag/app-release.apk.sha256',
        },
      ],
};

void main() {
  group('versionCodeFromTag', () {
    test('matches the release workflow formula', () {
      expect(versionCodeFromTag('v0.2.1'), 201);
      expect(versionCodeFromTag('v1.12.3'), 11203);
      expect(versionCodeFromTag('2.0.0'), 20000);
    });

    test('rejects tags outside the formula', () {
      expect(versionCodeFromTag('v1.2.3-beta'), isNull);
      expect(versionCodeFromTag('v1.100.0'), isNull);
      expect(versionCodeFromTag('latest'), isNull);
    });
  });

  group('ReleaseInfo.fromGitHubJson', () {
    test('parses apk and checksum assets', () {
      final r = ReleaseInfo.fromGitHubJson(_release(), _source);
      expect(r.tag, 'v0.3.0');
      expect(r.versionCode, 300);
      expect(r.apkSize, 1234);
      expect(r.apkUrl.path, endsWith('/app-release.apk'));
      expect(r.checksumUrl?.path, endsWith('/app-release.apk.sha256'));
      expect(r.notes, '## Changes');
    });

    test('checksum is optional', () {
      final json = _release();
      (json['assets'] as List).removeLast();
      expect(ReleaseInfo.fromGitHubJson(json, _source).checksumUrl, isNull);
    });

    test('missing apk asset fails', () {
      expect(
        () => ReleaseInfo.fromGitHubJson(_release(assets: []), _source),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.noApkAsset,
          ),
        ),
      );
    });

    test('ignores download urls off github.com or not https', () {
      for (final url in [
        'https://evil.example/app-release.apk',
        'http://github.com/x/y/app-release.apk',
      ]) {
        final json = _release(
          assets: [
            {'name': 'app-release.apk', 'browser_download_url': url},
          ],
        );
        expect(
          () => ReleaseInfo.fromGitHubJson(json, _source),
          throwsA(isA<UpdateException>()),
        );
      }
    });

    test('unrecognized tag fails', () {
      expect(
        () => ReleaseInfo.fromGitHubJson(_release(tag: 'nightly'), _source),
        throwsA(isA<UpdateException>()),
      );
    });
  });

  test('parseChecksumFile reads sha256sum format', () {
    final hex = 'a' * 64;
    expect(parseChecksumFile('$hex  app-release.apk\n'), hex);
    expect(parseChecksumFile(hex.toUpperCase()), hex);
    expect(parseChecksumFile('not-a-hash app-release.apk'), isNull);
  });

  group('UpdateSource', () {
    test('validates repo names', () {
      expect(UpdateSource.isValidRepo('moezakura/mux-pod'), isTrue);
      expect(UpdateSource.isValidRepo('a/b.c_d-e'), isTrue);
      expect(UpdateSource.isValidRepo('../etc'), isFalse);
      expect(UpdateSource.isValidRepo('owner/repo/extra'), isFalse);
      expect(UpdateSource.isValidRepo(''), isFalse);
    });

    test('normalizes fingerprints', () {
      expect(UpdateSource.normalizeFingerprint('AB:CD:0F'), 'abcd0f');
    });
  });
}
