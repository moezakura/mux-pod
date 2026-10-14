import 'dart:io';

import 'package:crypto/crypto.dart';

import 'update_failure.dart';
import 'updater_platform.dart';

/// Which checks a verified download passed. Shown to the user.
class VerificationReport {
  const VerificationReport({
    required this.checksumVerified,
    this.keyRotated = false,
  });

  /// False when the release published no checksum (older releases). The
  /// signature check still covers integrity: APK Signature Scheme v2+
  /// signs the whole file.
  final bool checksumVerified;

  /// The APK is signed with a new key that the installed app's key
  /// authorized through APK Signature Scheme v3 rotation.
  final bool keyRotated;
}

Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Throws [UpdateException] if [actual] differs from [expected].
void verifyChecksum({required String expected, required String actual}) {
  if (expected.toLowerCase() != actual.toLowerCase()) {
    throw UpdateException(
      UpdateFailure.checksumMismatch,
      'expected $expected, got $actual',
    );
  }
}

/// Decides whether [apk] may replace [installed]. Returns true if the APK
/// uses a rotated signing key. Throws [UpdateException].
///
/// - same package name
/// - strictly newer versionCode (no downgrades / reinstalls)
/// - signed by the same certificate set as the installed app, or (single
///   signer) by a rotated key whose v3 lineage includes the installed
///   app's certificate — the same rule Android applies
/// - if [pinnedCertSha256] is set, it must be the APK's signer or in its lineage
///
/// Android enforces the signature rule again at install time; checking it
/// here first means a bad download is rejected with a clear message and
/// never reaches the system installer.
bool verifyApkIdentity({
  required PackageIdentity? apk,
  required PackageIdentity installed,
  String? pinnedCertSha256,
}) {
  if (apk == null) {
    throw const UpdateException(UpdateFailure.invalidApk);
  }
  if (apk.packageName != installed.packageName) {
    throw UpdateException(UpdateFailure.wrongPackage, apk.packageName);
  }
  if (apk.signerSha256.isEmpty) {
    throw const UpdateException(UpdateFailure.signatureUnreadable);
  }
  final sameSigners =
      apk.signerSha256.length == installed.signerSha256.length &&
      apk.signerSha256.containsAll(installed.signerSha256);
  final rotated =
      !sameSigners &&
      apk.signerSha256.length == 1 &&
      installed.signerSha256.length == 1 &&
      apk.signerHistorySha256.contains(installed.signerSha256.single);
  if (!sameSigners && !rotated) {
    throw const UpdateException(UpdateFailure.signatureMismatch);
  }
  if (pinnedCertSha256 != null &&
      !apk.signerSha256.contains(pinnedCertSha256) &&
      !apk.signerHistorySha256.contains(pinnedCertSha256)) {
    throw const UpdateException(UpdateFailure.signatureMismatch, 'pin');
  }
  if (apk.versionCode <= installed.versionCode) {
    throw UpdateException(
      UpdateFailure.notNewer,
      '${apk.versionCode} <= ${installed.versionCode}',
    );
  }
  return rotated;
}
