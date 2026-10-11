import 'dart:io';

/// Where the in-app updater looks for releases. Fixed at build time.
///
/// The release workflow passes `--dart-define=UPDATE_REPO=${{ github.repository }}`,
/// so a fork that publishes its own releases updates from its own repo with
/// no code changes. Trust does not come from the repo name: a downloaded APK
/// must be signed with the same certificate as the *installed* app, so a
/// build signed with your own key only ever accepts APKs signed with that key.
///
/// Optional build-time overrides:
/// - `UPDATE_REPO`        GitHub `owner/name` to read releases from.
/// - `UPDATE_APK_ASSET`   Release asset file name of the APK.
/// - `UPDATE_CERT_SHA256` Additionally pin the signing certificate (hex SHA-256).
class UpdateSource {
  const UpdateSource({
    required this.repo,
    required this.apkAssetName,
    this.pinnedCertSha256,
    this.isReleaseBuild = false,
  });

  static const String defaultRepo = 'moezakura/mux-pod';
  static const String defaultApkAsset = 'app-release.apk';

  static const String _repo = String.fromEnvironment(
    'UPDATE_REPO',
    defaultValue: defaultRepo,
  );
  static const String _asset = String.fromEnvironment(
    'UPDATE_APK_ASSET',
    defaultValue: defaultApkAsset,
  );
  static const String _pin = String.fromEnvironment('UPDATE_CERT_SHA256');
  static const String _appVersion = String.fromEnvironment('APP_VERSION');

  /// The source compiled into this build.
  static UpdateSource fromEnvironment() => UpdateSource(
    repo: isValidRepo(_repo) ? _repo : defaultRepo,
    apkAssetName: _asset,
    pinnedCertSha256: _pin.isEmpty ? null : normalizeFingerprint(_pin),
    isReleaseBuild: _appVersion.isNotEmpty,
  );

  /// GitHub `owner/name`.
  final String repo;

  /// File name of the APK asset attached to each release.
  final String apkAssetName;

  /// Optional extra pin on the signing certificate (lowercase hex, no colons).
  final String? pinnedCertSha256;

  /// True for builds produced by the release workflow (APP_VERSION is set).
  /// Automatic checks default to on only for these; local builds can still
  /// check manually.
  final bool isReleaseBuild;

  /// Checksum asset published next to the APK (`sha256sum` format).
  String get checksumAssetName => '$apkAssetName.sha256';

  Uri get latestReleaseApi =>
      Uri.https('api.github.com', '/repos/$repo/releases/latest');

  Uri get releasesPage => Uri.https('github.com', '/$repo/releases');

  /// Self-updating via APK is Android-only.
  static bool get isPlatformSupported => Platform.isAndroid;

  static final RegExp _repoPattern = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$',
  );

  static bool isValidRepo(String repo) => _repoPattern.hasMatch(repo);

  /// `AB:CD:..` / `abcd..` → `abcd..`
  static String normalizeFingerprint(String fp) =>
      fp.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toLowerCase();
}
