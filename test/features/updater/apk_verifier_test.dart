import 'dart:io';

import 'package:flutter_muxpod/features/updater/apk_verifier.dart';
import 'package:flutter_muxpod/features/updater/update_failure.dart';
import 'package:flutter_muxpod/features/updater/updater_platform.dart';
import 'package:flutter_test/flutter_test.dart';

const _installed = PackageIdentity(
  packageName: 'si.mox.mux_pod',
  versionCode: 201,
  signerSha256: {'aaaa'},
);

PackageIdentity _apk({
  String pkg = 'si.mox.mux_pod',
  int code = 300,
  Set<String> signers = const {'aaaa'},
  Set<String> history = const {},
}) => PackageIdentity(
  packageName: pkg,
  versionCode: code,
  signerSha256: signers,
  signerHistorySha256: history,
);

Matcher _fails(UpdateFailure f) => throwsA(
  isA<UpdateException>().having((e) => e.failure, 'failure', f),
);

void main() {
  group('verifyApkIdentity', () {
    test('accepts newer apk with the same signer', () {
      verifyApkIdentity(apk: _apk(), installed: _installed);
    });

    test('rejects unparseable apk', () {
      expect(
        () => verifyApkIdentity(apk: null, installed: _installed),
        _fails(UpdateFailure.invalidApk),
      );
    });

    test('rejects other package', () {
      expect(
        () => verifyApkIdentity(apk: _apk(pkg: 'evil'), installed: _installed),
        _fails(UpdateFailure.wrongPackage),
      );
    });

    test('rejects unreadable signature', () {
      expect(
        () => verifyApkIdentity(apk: _apk(signers: {}), installed: _installed),
        _fails(UpdateFailure.signatureUnreadable),
      );
    });

    test('accepts a rotated key whose lineage includes the installed key', () {
      expect(
        verifyApkIdentity(
          apk: _apk(signers: {'bbbb'}, history: {'aaaa', 'bbbb'}),
          installed: _installed,
        ),
        isTrue,
      );
      expect(verifyApkIdentity(apk: _apk(), installed: _installed), isFalse);
    });

    test('rejects a rotated key whose lineage lacks the installed key', () {
      expect(
        () => verifyApkIdentity(
          apk: _apk(signers: {'bbbb'}, history: {'cccc', 'bbbb'}),
          installed: _installed,
        ),
        _fails(UpdateFailure.signatureMismatch),
      );
    });

    test('pin may match the lineage', () {
      verifyApkIdentity(
        apk: _apk(signers: {'bbbb'}, history: {'aaaa', 'bbbb'}),
        installed: _installed,
        pinnedCertSha256: 'aaaa',
      );
    });

    test('rejects different or extra signers', () {
      for (final signers in [
        <String>{'bbbb'},
        <String>{'aaaa', 'bbbb'},
      ]) {
        expect(
          () => verifyApkIdentity(
            apk: _apk(signers: signers),
            installed: _installed,
          ),
          _fails(UpdateFailure.signatureMismatch),
        );
      }
    });

    test('enforces pinned certificate', () {
      expect(
        () => verifyApkIdentity(
          apk: _apk(),
          installed: _installed,
          pinnedCertSha256: 'cccc',
        ),
        _fails(UpdateFailure.signatureMismatch),
      );
      verifyApkIdentity(
        apk: _apk(),
        installed: _installed,
        pinnedCertSha256: 'aaaa',
      );
    });

    test('rejects same or older version', () {
      for (final code in [201, 200]) {
        expect(
          () => verifyApkIdentity(apk: _apk(code: code), installed: _installed),
          _fails(UpdateFailure.notNewer),
        );
      }
    });
  });

  test('verifyChecksum compares case-insensitively', () {
    verifyChecksum(expected: 'ABCD', actual: 'abcd');
    expect(
      () => verifyChecksum(expected: 'abcd', actual: 'abce'),
      _fails(UpdateFailure.checksumMismatch),
    );
  });

  test('sha256OfFile', () async {
    final dir = await Directory.systemTemp.createTemp('updater_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/f')..writeAsStringSync('abc');
    expect(
      await sha256OfFile(file),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
