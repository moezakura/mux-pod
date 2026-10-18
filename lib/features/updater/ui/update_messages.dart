import '../../../l10n/app_localizations.dart';
import '../update_failure.dart';

/// Localized, user-facing text for an [UpdateException].
String updateErrorMessage(AppLocalizations l10n, UpdateException e) =>
    switch (e.failure) {
      UpdateFailure.network => l10n.updaterErrorNetwork,
      UpdateFailure.rateLimited => l10n.updaterErrorRateLimited,
      UpdateFailure.noRelease => l10n.updaterErrorNoRelease,
      UpdateFailure.noApkAsset => l10n.updaterErrorNoApk,
      UpdateFailure.invalidApk => l10n.updaterErrorInvalidApk,
      UpdateFailure.checksumMismatch => l10n.updaterErrorChecksum,
      UpdateFailure.wrongPackage => l10n.updaterErrorPackage,
      UpdateFailure.signatureMismatch => l10n.updaterErrorSignature,
      UpdateFailure.signatureUnreadable => l10n.updaterErrorSignatureUnreadable,
      UpdateFailure.notNewer => l10n.updaterErrorNotNewer,
      UpdateFailure.installFailed => l10n.updaterErrorInstall(e.detail ?? '-'),
      UpdateFailure.unknown => l10n.updaterErrorUnknown(e.detail ?? '-'),
    };
