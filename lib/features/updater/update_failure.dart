/// Why an update step failed. Mapped to localized text in the UI layer.
enum UpdateFailure {
  network,
  rateLimited,
  noRelease,
  noApkAsset,
  invalidApk,
  checksumMismatch,
  wrongPackage,
  signatureMismatch,

  /// Android returned no signature for the download (seen on old releases
  /// of Android). Fails closed; the user can install from the release page.
  signatureUnreadable,
  notNewer,
  installFailed,
  unknown,
}

class UpdateException implements Exception {
  const UpdateException(this.failure, [this.detail]);

  final UpdateFailure failure;

  /// Free-form detail for logs / the generic error messages.
  final String? detail;

  @override
  String toString() =>
      'UpdateException(${failure.name}${detail == null ? '' : ': $detail'})';
}
