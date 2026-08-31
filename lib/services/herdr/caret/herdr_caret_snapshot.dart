// inventory: HERDR-CARET-SNAPSHOT-000
/// herdr-caret-helper が stdout の単一 JSON 行で返すカーソルスナップショットの
/// モデルと検証。
///
/// helper JSON 出力（Phase 3 契約）:
/// ```json
/// {"cursor":{"x":<u16>,"y":<u16>,"visible":<bool>,"shape":<u8>}|null,
///  "frameWidth":<u16>,"frameHeight":<u16>,"protocolVersion":17|20,"paneId":"<str>"}
/// ```
///
/// - `cursor: null` は「非表示カーソル」の正当な観測として表現する
///   （[visible] == false・位置不明のため [x]/[y] は null）。
/// - 位置は 0-based の u16。正当な `(0, 0)` と「不明」を区別するため
///   [x]/[y] は nullable にする（計画 L5: nullable snapshot）。
/// - 範囲外座標・不正 protocol・破損 JSON・pane ID 不一致は clamp せず
///   検証失敗（[FormatException]）にする。
library;

import 'dart:convert';

/// helper が対応する protocol 番号（17 / 20 のみ）。
const Set<int> kHerdrCaretSupportedProtocols = {17, 20};

/// u16 の上限（x / y / frameWidth / frameHeight 共通）。
const int kHerdrCaretU16Max = 0xFFFF;

/// u8 の上限（shape / DECSCUSR 相当値）。
const int kHerdrCaretShapeMax = 0xFF;

/// helper の stdout 最大長（manager 側で打ち切る。ここでは既定値の参照）。
const int kHerdrCaretMaxStdoutBytes = 64 * 1024;

/// カーソル位置スナップショット。
class HerdrCaretSnapshot {
  /// カーソル X（0-based・文字セル単位）。不明なら null。
  final int? x;

  /// カーソル Y（0-based・文字セル単位）。不明なら null。
  final int? y;

  /// カーソルが表示中かどうか。
  ///
  /// `cursor: null` や `visible: false` のとき false。この状態は描画層まで
  /// 保持し、MuxPod 側のカーソルを描画しないために使う。
  final bool visible;

  /// DECSCUSR 相当のカーソル形状（u8）。
  final int shape;

  /// 取得時点の frame 幅（文字セル数・検証用）。
  final int frameWidth;

  /// 取得時点の frame 高さ（文字セル数・検証用）。
  final int frameHeight;

  /// helper が話した protocol 番号（17 または 20）。
  final int protocolVersion;

  /// 対象 pane ID（実値 `wN:pN`。opaque に保持）。
  final String paneId;

  /// 観測時刻。
  final DateTime capturedAt;

  const HerdrCaretSnapshot({
    required this.x,
    required this.y,
    required this.visible,
    required this.shape,
    required this.frameWidth,
    required this.frameHeight,
    required this.protocolVersion,
    required this.paneId,
    required this.capturedAt,
  });

  /// カーソルが非表示かどうか（描画層でカーソルを描かない判定に使う）。
  bool get isHidden => !visible;

  /// 位置が既知かどうか（`cursor: null` の観測では false）。
  bool get hasPosition => x != null && y != null;

  /// helper の単一 JSON 行からパース・検証する。
  ///
  /// [expectedPaneId]: 要求した pane ID。helper 応答と不一致なら
  /// [FormatException]（stale / 誤応答の検出）。
  /// [capturedAt]: 観測時刻（省略時は [DateTime.now]）。
  ///
  /// 検証失敗（破損 JSON・範囲外座標・不正 protocol・pane 不一致）は
  /// [FormatException] を投げる（clamp しない）。
  static HerdrCaretSnapshot fromHelperJson(
    String json, {
    required String expectedPaneId,
    DateTime? capturedAt,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('Helper output is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Helper output is not a JSON object');
    }

    final int? x;
    final int? y;
    final bool visible;
    final int shape;
    final cursor = decoded['cursor'];
    if (cursor == null) {
      // 「非表示カーソル」の正当な観測: 位置は不明として扱う。
      x = null;
      y = null;
      visible = false;
      shape = 0;
    } else if (cursor is Map<String, dynamic>) {
      x = _requiredU16(cursor, 'x');
      y = _requiredU16(cursor, 'y');
      visible = _requiredBool(cursor, 'visible');
      shape = _requiredU8(cursor, 'shape');
    } else {
      throw const FormatException('cursor must be an object or null');
    }

    final frameWidth = _requiredU16(decoded, 'frameWidth');
    final frameHeight = _requiredU16(decoded, 'frameHeight');

    final protocolVersion = decoded['protocolVersion'];
    if (protocolVersion is! int ||
        !kHerdrCaretSupportedProtocols.contains(protocolVersion)) {
      throw FormatException('Unsupported protocolVersion: $protocolVersion');
    }

    final paneId = decoded['paneId'];
    if (paneId is! String || !isValidPaneId(paneId)) {
      throw const FormatException('Invalid paneId in helper output');
    }
    if (paneId != expectedPaneId) {
      throw FormatException('Pane id mismatch in helper output');
    }

    return HerdrCaretSnapshot(
      x: x,
      y: y,
      visible: visible,
      shape: shape,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      protocolVersion: protocolVersion,
      paneId: paneId,
      capturedAt: capturedAt ?? DateTime.now(),
    );
  }

  /// pane ID の書式検証（長さ 1..64・印字可能 ASCII・制御文字なし）。
  static bool isValidPaneId(String paneId) {
    if (paneId.isEmpty || paneId.length > 64) return false;
    for (final unit in paneId.codeUnits) {
      if (unit < 0x20 || unit > 0x7E) return false;
    }
    return true;
  }

  static int _requiredU16(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! int || value < 0 || value > kHerdrCaretU16Max) {
      throw FormatException('$key must be a u16 (0..$kHerdrCaretU16Max)');
    }
    return value;
  }

  static int _requiredU8(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! int || value < 0 || value > kHerdrCaretShapeMax) {
      throw FormatException('$key must be a u8 (0..$kHerdrCaretShapeMax)');
    }
    return value;
  }

  static bool _requiredBool(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! bool) throw FormatException('$key must be a bool');
    return value;
  }

  @override
  String toString() =>
      'HerdrCaretSnapshot(paneId=$paneId, '
      '${x == null ? 'pos=unknown' : 'pos=($x,$y)'}, '
      'visible=$visible, shape=$shape, '
      'frame=${frameWidth}x$frameHeight, protocol=$protocolVersion, '
      'at=${capturedAt.toIso8601String()})';
}
