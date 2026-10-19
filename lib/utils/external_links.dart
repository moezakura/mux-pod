/// 外部リンク起動の単一ソース（https/http 判定 + OS 外部ブラウザ起動）。
///
/// scheme ガードは [Uri.tryParse] の scheme 小文字正規化に従う:
/// `HTTPS:` / `Http:` 等の大文字表記ゆれは https/http として受理され、
/// `javascript:` 等の危険 scheme は正規化されず確実に reject される (C1)。
/// fail-closed（大文字拒否）案は markdown 側の一字不変契約違反のため採用しない。
library;

import 'package:url_launcher/url_launcher.dart';

/// https/http のみを [Uri] として受理する scheme ガード。
///
/// `https://` / `http://`（scheme の大文字表記は正規化により受理）以外は
/// throw せず `null` を返す（`#anchor`・`mailto:`・`data:`・`javascript:`・
/// `file:` 等はタップ無視）。副作用なしの純関数。
Uri? tryParseExternalHttpUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  return uri;
}

/// [uri] を OS 外部ブラウザで起動する（about_section / markdown 先例パターン）。
///
/// `canLaunchUrl` が false（ブラウザ不在・scheme 未対応等）の場合は
/// 何もせず握りつぶす（クラッシュしない・診断ログはフォローアップ Issue）。
Future<void> launchExternalUri(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
