// inventory: HERDR-HYPERLINK-JSON-000
/// `hyperlinks` と `scrollback-links`（1窓あたり）で共通の出力フィールド
/// （`frameWidth`/`frameHeight`/`truncated`/`links`/`rowHashes`）を手書きで
/// 検証し、domain 型 [PaneHyperlinks] へ変換する共通ロジック
/// （`links` の形式と出力量の詰め方は `hyperlinks` と同じ）。
///
/// [HerdrHyperlinkHelperManager] と
/// [HerdrScrollbackLinkHelperManager] の両方から呼ばれる。呼び出し側
/// が JSON オブジェクトへの decode と、この関数のスコープ外のフィールド
/// （`paneId`/`protocolVersion`/`requestedOffset`/`actualOffset`/`restore`
/// など）の検証を担う。
///
/// 検証失敗は [FormatException] を投げる（clamp しない。呼び出し側の
/// manager がこれを捕捉し [HerdrCaretHelperException] へ変換する）。
/// 例外メッセージにはフィールド名だけを含め、URL・stdout 本文は含めない。
library;

import '../../backend/domain/pane_frame_reader.dart';

/// u16 の上限（row / col / frameWidth / frameHeight 共通）。
const int kHerdrHyperlinkU16Max = 0xFFFF;

/// 行フィンガープリントの書式（16桁0埋め小文字hex）。
final RegExp _fingerprintPattern = RegExp(r'^[0-9a-f]{16}$');

/// [map] から `frameWidth`/`frameHeight`/`truncated`/`links`/`rowHashes` を
/// 検証・変換する。
PaneHyperlinks parseHyperlinkFields(Map<String, dynamic> map) {
  final frameWidth = requiredU16(map, 'frameWidth');
  final frameHeight = requiredU16(map, 'frameHeight');
  final truncated = requiredBool(map, 'truncated');

  final linksRaw = map['links'];
  if (linksRaw is! List) {
    throw const FormatException('links must be an array');
  }
  final links = List<PaneHyperlink>.unmodifiable(
    linksRaw.map((entry) => _parseLink(entry, frameWidth, frameHeight)),
  );

  final rowHashesRaw = map['rowHashes'];
  if (rowHashesRaw is! List) {
    throw const FormatException('rowHashes must be an array');
  }
  final rowFingerprintsMutable = <int, String>{};
  for (final entry in rowHashesRaw) {
    final (row, hex) = _parseRowHash(entry, frameHeight);
    if (rowFingerprintsMutable.containsKey(row)) {
      // Map へ畳み込むと黙って上書きされてしまうため、事前に重複を拒否する。
      throw const FormatException('rowHashes contains a duplicate row');
    }
    rowFingerprintsMutable[row] = hex;
  }
  final rowFingerprints = Map<int, String>.unmodifiable(rowFingerprintsMutable);

  return PaneHyperlinks(
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    links: links,
    rowFingerprints: rowFingerprints,
    truncated: truncated,
  );
}

PaneHyperlink _parseLink(Object? entry, int frameWidth, int frameHeight) {
  if (entry is! Map<String, dynamic>) {
    throw const FormatException('links entry must be an object');
  }
  final url = entry['url'];
  if (url is! String || url.isEmpty) {
    throw const FormatException('links[].url must be a non-empty string');
  }
  if (_containsControlChar(url)) {
    // サニタイズは helper 側の責任だが、アプリ側も fail-closed で
    // 受ける。スキームの許可判定はしない
    // （openExternalLink に任せる。ここでは制御文字だけを見る）。
    throw const FormatException(
      'links[].url must not contain control characters',
    );
  }
  final rangesRaw = entry['ranges'];
  if (rangesRaw is! List || rangesRaw.isEmpty) {
    throw const FormatException('links[].ranges must be a non-empty array');
  }
  final ranges = List<PaneHyperlinkRange>.unmodifiable(
    rangesRaw.map((r) => _parseRange(r, frameWidth, frameHeight)),
  );
  return PaneHyperlink(url: url, ranges: ranges);
}

PaneHyperlinkRange _parseRange(Object? entry, int frameWidth, int frameHeight) {
  if (entry is! List || entry.length != 3) {
    throw const FormatException('range must be [row, startCol, endCol]');
  }
  final row = requiredIndex(entry[0], frameHeight, 'range row');
  final startCol = requiredIndex(entry[1], frameWidth, 'range startCol');
  final endCol = requiredIndex(entry[2], frameWidth, 'range endCol');
  if (startCol > endCol) {
    throw const FormatException('range startCol must be <= endCol');
  }
  return PaneHyperlinkRange(row: row, startCol: startCol, endCol: endCol);
}

/// `[row, "hex"]` の1要素を検証する（重複検出は呼び出し側が担う）。
(int, String) _parseRowHash(Object? entry, int frameHeight) {
  if (entry is! List || entry.length != 2) {
    throw const FormatException('rowHashes entry must be [row, hex]');
  }
  final row = requiredIndex(entry[0], frameHeight, 'rowHashes row');
  final hex = entry[1];
  if (hex is! String || !_fingerprintPattern.hasMatch(hex)) {
    throw const FormatException('rowHashes hex must be 16-digit lowercase hex');
  }
  return (row, hex);
}

/// C0（0x00..0x1F）・DEL（0x7F）のいずれかを含むかどうか。
bool _containsControlChar(String value) {
  for (final unit in value.codeUnits) {
    if (unit <= 0x1F || unit == 0x7F) return true;
  }
  return false;
}

/// u16 必須フィールドの検証（[HerdrHyperlinkHelperManager]・
/// [HerdrScrollbackLinkHelperManager] の両方から使う共通ヘルパー）。
int requiredU16(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int || value < 0 || value > kHerdrHyperlinkU16Max) {
    throw FormatException('$key must be a u16 (0..$kHerdrHyperlinkU16Max)');
  }
  return value;
}

/// bool 必須フィールドの検証。
bool requiredBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('$key must be a bool');
  return value;
}

/// 0 <= value < [bound] の u16 インデックス検証（row < frameHeight、
/// col < frameWidth の境界チェック）。
int requiredIndex(Object? value, int bound, String label) {
  if (value is! int || value < 0 || value >= bound) {
    throw FormatException('$label must be in range 0..<$bound');
  }
  return value;
}
