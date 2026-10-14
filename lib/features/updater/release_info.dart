import 'update_failure.dart';
import 'update_source.dart';

/// Android versionCode for a release tag.
///
/// Mirrors the formula in `.github/workflows/release.yml`:
/// `MAJOR * 10000 + MINOR * 100 + PATCH`. Returns null for tags that don't
/// fit it (pre-release suffixes, MINOR/PATCH > 99).
int? versionCodeFromTag(String tag) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(tag.trim());
  if (m == null) return null;
  final major = int.parse(m.group(1)!);
  final minor = int.parse(m.group(2)!);
  final patch = int.parse(m.group(3)!);
  if (minor > 99 || patch > 99) return null;
  return major * 10000 + minor * 100 + patch;
}

/// The parts of a GitHub release the updater needs.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.versionCode,
    required this.notes,
    required this.htmlUrl,
    required this.apkUrl,
    required this.apkSize,
    this.checksumUrl,
    this.publishedAt,
  });

  final String tag;
  final int versionCode;
  final String notes;
  final Uri htmlUrl;
  final Uri apkUrl;
  final int apkSize;

  /// Null for releases published before checksums were added.
  final Uri? checksumUrl;
  final DateTime? publishedAt;

  /// Parses a `GET /repos/{repo}/releases/latest` response.
  ///
  /// Throws [UpdateException] if the release can't be used for an update.
  factory ReleaseInfo.fromGitHubJson(
    Map<String, dynamic> json,
    UpdateSource source,
  ) {
    final tag = json['tag_name'];
    if (tag is! String) {
      throw const UpdateException(UpdateFailure.noRelease, 'missing tag_name');
    }
    final versionCode = versionCodeFromTag(tag);
    if (versionCode == null) {
      throw UpdateException(UpdateFailure.noRelease, 'unrecognized tag $tag');
    }

    final assets = (json['assets'] as List?)?.whereType<Map>() ?? const [];
    Map? asset(String name) {
      for (final a in assets) {
        if (a['name'] == name) return a;
      }
      return null;
    }

    final apk = asset(source.apkAssetName);
    final apkUrl = _githubUrl(apk?['browser_download_url']);
    if (apk == null || apkUrl == null) {
      throw UpdateException(UpdateFailure.noApkAsset, tag);
    }
    final checksum = asset(source.checksumAssetName);

    return ReleaseInfo(
      tag: tag,
      versionCode: versionCode,
      notes: (json['body'] as String?) ?? '',
      htmlUrl: _githubUrl(json['html_url']) ?? source.releasesPage,
      apkUrl: apkUrl,
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      checksumUrl: _githubUrl(checksum?['browser_download_url']),
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
    );
  }

  /// Only accept https URLs on github.com; anything else is ignored.
  static Uri? _githubUrl(Object? raw) {
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      return null;
    }
    return uri;
  }
}

/// Extracts the hex digest from a `sha256sum`-style file (`<hex>  <name>`).
String? parseChecksumFile(String content) {
  final token = content.trim().split(RegExp(r'\s+')).first.toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(token) ? token : null;
}
