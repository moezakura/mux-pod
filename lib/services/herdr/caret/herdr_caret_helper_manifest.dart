// inventory: HERDR-CARET-MANIFEST-000
/// herdr-caret-helper の配布 manifest（assets 同梱）の読み取りと
/// platform 選択・バイナリ検証用モデル。
///
/// manifest 構造（Phase 2b が CI で生成・assets へ同梱する固定契約）:
/// ```json
/// {
///   "version": 1,
///   "helperName": "herdr-caret-helper",
///   "platforms": [
///     {
///       "id": "linux-x86_64",
///       "os": "linux",
///       "arch": "x86_64",
///       "asset": "assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper",
///       "size": <int>,
///       "sha256": "<hex>"
///     },
///     { "id": "linux-aarch64", ... }
///   ]
/// }
/// ```
///
/// Phase 3 の対象は Linux x86_64 / aarch64 のみ。非 Linux・未知 arch は
/// [selectFor] が null を返し、呼び出し側（helper manager）が unsupported と
/// 分類する。文字列パース・platform 選択は純 Dart（テスト可能）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// manifest の想定 version（将来変更時はここで固定契約を更新する）。
const int kHerdrCaretHelperManifestVersion = 1;

/// manifest のアセットパス（pubspec.yaml の assets 登録と一致させる）。
const String kHerdrCaretHelperManifestAsset =
    'assets/herdr-caret-helper/manifest.json';

/// サポートする host OS の正規化名（uname -s の "Linux" 由来）。
const String kHerdrCaretHelperOsLinux = 'linux';

/// [raw] をハッシュ比較用のバイト列から hex 文字列にする（sha256）。
///
/// ローカル bundle・リモート配置物の両方の検証に使う。
String hexSha256(List<int> bytes) =>
    sha256.convert(bytes).toString().toLowerCase();

/// manifest 内の 1 platform エントリ。
class HerdrCaretHelperPlatform {
  /// platform ID（例: "linux-x86_64"）。
  final String id;

  /// OS の正規化名（例: "linux"）。
  final String os;

  /// arch の正規化名（例: "x86_64" / "aarch64"）。
  final String arch;

  /// bundle 上の helper バイナリへの asset パス。
  final String asset;

  /// 期待バイト数。
  final int size;

  /// 期待 sha256（小文字 hex）。
  final String sha256;

  const HerdrCaretHelperPlatform({
    required this.id,
    required this.os,
    required this.arch,
    required this.asset,
    required this.size,
    required this.sha256,
  });

  /// [bytes] が manifest の size / sha256 と一致するか。
  ///
  /// size 不一致または sha256 不一致なら false（一致時のみ true）。
  bool matchesBytes(Uint8List bytes) =>
      bytes.length == size &&
      hexSha256(bytes) == sha256.toLowerCase();

  @override
  String toString() =>
      'HerdrCaretHelperPlatform($id, os=$os, arch=$arch, '
      'asset=$asset, size=$size, sha256=${sha256.substring(0, 12)}…)';
}

/// manifest 全体。
class HerdrCaretHelperManifest {
  /// manifest 形式 version。
  final int version;

  /// helper のファイル名（配置先の最終ファイル名）。
  final String helperName;

  /// platform エントリ一覧。
  final List<HerdrCaretHelperPlatform> platforms;

  const HerdrCaretHelperManifest({
    required this.version,
    required this.helperName,
    required this.platforms,
  });

  /// JSON 文字列からパースする（構造不正・version 不一致は
  /// [FormatException]）。
  static HerdrCaretHelperManifest fromJson(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('Invalid manifest JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid manifest JSON: not an object');
    }
    final version = decoded['version'];
    if (version is! int) {
      throw const FormatException('Invalid manifest: version must be int');
    }
    if (version != kHerdrCaretHelperManifestVersion) {
      throw FormatException(
        'Unsupported manifest version: $version '
        '(expected $kHerdrCaretHelperManifestVersion)',
      );
    }
    final helperName = decoded['helperName'];
    if (helperName is! String || helperName.isEmpty) {
      throw const FormatException('Invalid manifest: helperName');
    }
    final rawPlatforms = decoded['platforms'];
    if (rawPlatforms is! List) {
      throw const FormatException('Invalid manifest: platforms must be list');
    }
    final platforms = <HerdrCaretHelperPlatform>[];
    for (final raw in rawPlatforms) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid manifest: platform entry must be object',
        );
      }
      platforms.add(
        HerdrCaretHelperPlatform(
          id: _requireString(raw, 'id'),
          os: _requireString(raw, 'os'),
          arch: _requireString(raw, 'arch'),
          asset: _requireString(raw, 'asset'),
          size: _requireInt(raw, 'size'),
          sha256: _requireString(raw, 'sha256'),
        ),
      );
    }
    if (platforms.isEmpty) {
      throw const FormatException('Invalid manifest: no platforms');
    }
    return HerdrCaretHelperManifest(
      version: version,
      helperName: helperName,
      platforms: platforms,
    );
  }

  /// assets から manifest を読み込む。
  ///
  /// [bundle] 省略時は [rootBundle]。テストでは差し替え可能な loader を
  /// [loadString] として注入するか、[HerdrCaretHelperManifest.fromJson] を
  /// 直接使う。
  static Future<HerdrCaretHelperManifest> load({
    AssetBundle? bundle,
    String path = kHerdrCaretHelperManifestAsset,
  }) async {
    final text = await (bundle ?? rootBundle).loadString(path);
    return fromJson(text);
  }

  /// [os]（uname -s）と [arch]（uname -m）から対応 platform を選ぶ。
  ///
  /// - OS は小文字正規化（"Linux" → "linux"）。
  /// - arch は別名を正規化（"amd64" → "x86_64"、"arm64" → "aarch64"）。
  /// - 非 Linux / 未知 arch / manifest に無い組合せは null（= unsupported）。
  HerdrCaretHelperPlatform? selectFor(String os, String arch) {
    final normalizedOs = normalizeOs(os);
    final normalizedArch = normalizeArch(arch);
    if (normalizedOs != kHerdrCaretHelperOsLinux) return null;
    for (final platform in platforms) {
      if (normalizeOs(platform.os) == normalizedOs &&
          normalizeArch(platform.arch) == normalizedArch) {
        return platform;
      }
    }
    return null;
  }

  /// OS 名を正規化する（uname 出力と manifest 値を両方正規化して比較）。
  static String normalizeOs(String raw) => raw.trim().toLowerCase();

  /// arch 名を正規化する（別名を統一。未知 arch はそのまま小文字化）。
  static String normalizeArch(String raw) {
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'amd64' => 'x86_64',
      'arm64' => 'aarch64',
      _ => normalized,
    };
  }
}

String _requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid manifest: $key must be non-empty string');
  }
  return value;
}

int _requireInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int || value < 0) {
    throw FormatException('Invalid manifest: $key must be non-negative int');
  }
  return value;
}