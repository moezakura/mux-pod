// Herdr OSC 8 ハイパーリンク: 行フィンガープリント（FNV-1a）と
// 本文の行・helper フレームの行の対応づけ。
//
// 純関数のみ（I/O・backend 依存なし）。フィンガープリント関数は Rust 側
// `tools/herdr-caret-helper/src/tracker.rs::row_fingerprint` と
// バイト単位で同じ出力になるよう共通テストベクタ
// `tools/herdr-caret-helper/testdata/fingerprint_vectors.json` で検証する。
//
// lib/services 配下（backend/表示レイヤーに依存しない純粋な整列ロジック）。
// `HerdrHyperlinkRange` もここで定義する（reader/cache（services 層）と
// widgets 層（overlay/reconciler）の双方が参照する共有型のため）。
// widgets 側は `herdr_hyperlink_overlay.dart` 経由でこの型を re-export する
// （lib/services → lib/screens の逆向き import を作らないため）。
library;

import 'dart:convert';
import 'dart:math' as math;

/// helper が返す 1 リンク範囲（表示セル単位・両端含む。helper 出力の
/// `ranges` 要素 `[row, startCol, endCol]` のうち row を除いた部分）。
final class HerdrHyperlinkRange {
  /// 開始列（0-based、表示セル単位）。
  final int startCol;

  /// 終了列（0-based、表示セル単位、この列を含む）。
  final int endCol;

  final String url;

  const HerdrHyperlinkRange({
    required this.startCol,
    required this.endCol,
    required this.url,
  });

  /// 値の等価性（`ScrollbackLinkCache.applyWindowResult` が
  /// 「内容が実際に変わったか」を判定するために使う）。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HerdrHyperlinkRange &&
          startCol == other.startCol &&
          endCol == other.endCol &&
          url == other.url);

  @override
  int get hashCode => Object.hash(startCol, endCol, url);
}

/// 64bit FNV-1a フィンガープリント。
///
/// Rust 実装（`tracker.rs`）と同一のアルゴリズム: offset basis
/// `0xcbf29ce484222325`、prime `0x100000001b3`、UTF-8 バイト列に対する
/// FNV-1a、0 埋め 16 桁小文字 hex。
class HerdrRowFingerprint {
  HerdrRowFingerprint._();

  static const int _offsetBasis = 0xcbf29ce484222325;
  static const int _prime = 0x100000001b3;

  /// 64bit FNV-1a ハッシュを 0 埋め 16 桁小文字 hex 文字列で返す。
  ///
  /// Dart の `int` は native では 64bit 符号付きで乗算・XOR は 64bit を
  /// 折り返す（Rust の `u64` の wrapping 演算と bit パターンが一致する）。
  /// 16進整形は符号ビットを正しく反映するため [BigInt.toUnsigned] を経由する
  /// （`int.toUnsigned(64)` は 64bit 幅では no-op になり負号が残るため使えない）。
  static String fnv1a64Hex(List<int> bytes) {
    var hash = _offsetBasis;
    for (final byte in bytes) {
      hash ^= byte;
      hash *= _prime;
    }
    return BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  /// 行のフィンガープリント。
  ///
  /// [displayText] は行の表示文字列（書かれたセルの文字を
  /// 連結し、全角文字の後半セルは含まない）を渡す前提。末尾の U+0020
  /// （半角スペース）のみを除去し、UTF-8 バイト列に対して FNV-1a を計算する。
  /// 除去後に空文字列になる行（空行）は `null`（フィンガープリントを出さない）。
  static String? rowFingerprint(String displayText) {
    var end = displayText.length;
    while (end > 0 && displayText.codeUnitAt(end - 1) == 0x20) {
      end--;
    }
    if (end == 0) return null;
    return fnv1a64Hex(utf8.encode(displayText.substring(0, end)));
  }
}

/// 多数決で採用された整列結果。
final class HerdrHyperlinkAlignment {
  /// 本文を読んだ時点とフレームを取った時点の行数差（採用された k）。
  final int k;

  const HerdrHyperlinkAlignment(this.k);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HerdrHyperlinkAlignment && k == other.k);

  @override
  int get hashCode => k.hashCode;
}

/// フレームの行 r（0-based）を本文の行 i（0-based）へ対応づける。
///
/// d = [windowOffset] + ([frameRows] − 1 − [frameRow])。
/// i = ([bodyLineCount] − 1 − d) + [k]。
/// 範囲外（i < 0 || i >= bodyLineCount）は対応する本文行が無い（`null`）。
int? alignFrameRowToBodyLine({
  required int frameRow,
  required int frameRows,
  required int windowOffset,
  required int bodyLineCount,
  required int k,
}) {
  final d = windowOffset + (frameRows - 1 - frameRow);
  final i = (bodyLineCount - 1 - d) + k;
  if (i < 0 || i >= bodyLineCount) return null;
  return i;
}

/// 多数決で本文行とフレーム行の対応の差 k を決める。
///
/// - [bodyFingerprints]: 本文の行フィンガープリント（index = 行 i、0-based。
///   空行は `null`）。
/// - [frameFingerprints]: helper フレームの行フィンガープリント（index = 行 r、
///   0-based。空行は `null`）。
/// - [windowOffset]: この窓の `offset_from_bottom`（a）。
///
/// 整列できない場合は `null` を返す（その窓のリンクを全て抑制）。
/// throw しない。純関数（副作用なし）。
HerdrHyperlinkAlignment? resolveHerdrHyperlinkAlignment({
  required List<String?> bodyFingerprints,
  required List<String?> frameFingerprints,
  required int windowOffset,
}) {
  final bodyLineCount = bodyFingerprints.length;
  final frameRows = frameFingerprints.length;

  // 本文中の出現回数（9回以上は「空行に近い行・繰り返し行」として投票除外）。
  // 同時に、9回未満の行だけを対象にフィンガープリント→本文行番号の索引を
  // 作る（1 エントリ最大 8 件）。フレーム行 × 本文全行の総当たりを避け、
  // 投票を「フレームの空でない行数 × 最大8」の線形時間にする
  // （スクロールモードは本文最大 20000 行・build 内で呼ばれるため）。
  final occurrences = <String, int>{};
  for (final fp in bodyFingerprints) {
    if (fp == null) continue;
    occurrences[fp] = (occurrences[fp] ?? 0) + 1;
  }
  final bodyIndicesByFingerprint = <String, List<int>>{};
  for (var i = 0; i < bodyLineCount; i++) {
    final fp = bodyFingerprints[i];
    if (fp == null) continue;
    if (occurrences[fp]! >= 9) continue;
    (bodyIndicesByFingerprint[fp] ??= <int>[]).add(i);
  }

  final nonEmptyFrameRows = <int>[];
  for (var row = 0; row < frameRows; row++) {
    if (frameFingerprints[row] != null) nonEmptyFrameRows.add(row);
  }
  if (nonEmptyFrameRows.isEmpty) return null;

  final votes = <int, int>{};
  for (final row in nonEmptyFrameRows) {
    final fp = frameFingerprints[row]!;
    final matches = bodyIndicesByFingerprint[fp];
    if (matches == null) continue;
    final d = windowOffset + (frameRows - 1 - row);
    for (final i in matches) {
      final k = i - (bodyLineCount - 1 - d);
      votes[k] = (votes[k] ?? 0) + 1;
    }
  }
  if (votes.isEmpty) return null;

  final sorted = votes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted.first;

  // 条件 (1): 得票がフレームの空でない行数の 50% 以上かつ
  // min(3, 空でない行数) 以上。
  if (2 * top.value < nonEmptyFrameRows.length) return null;
  if (top.value < math.min(3, nonEmptyFrameRows.length)) return null;

  // 条件 (2): 2 位の得票より多い（同点は不採用）。
  if (sorted.length > 1 && sorted[1].value >= top.value) return null;

  return HerdrHyperlinkAlignment(top.key);
}

/// 多数決による整列（差 k の決定）と、frame 幅の sanity チェック・
/// 行ごとの除外を合成し、
/// フレームの行ごとのリンク範囲を「本文行番号 → リンク範囲」の対応へ変換する
/// （採用した k と通過した行、または整列失敗を返す）。
///
/// 具体的な取得元の型（`PaneHyperlinks` 等）には依存しない純関数。
/// 型ごとの組み立ては reconciler に分離する。
///
/// - [frameLinksByRow]: helper フレームの行番号（0-based）→ その行のリンク
///   範囲。
/// - [frameWidth]: helper が実際に使った frame 幅をそのまま信頼する
///   （helper が読み取れた実 pty サイズを Dart から渡した値より優先して
///   使うため、Dart 側が独立に計算した「依頼幅」との一致はもはや
///   frame が正しいことの根拠にならない）。壊れたデータの sanity
///   チェックのみ（`frameWidth <= 0`）を行い、幅の不一致（本文と
///   frame で実際の折り返しが違う場合）は行単位のフィンガープリント
///   不一致として整列失敗・行単位除外が捕捉する。
/// - [bodyFingerprints] / [frameFingerprints] / [windowOffset]: 整列
///   （k が決まらない窓は全リンクを抑制）。
/// - 整列後、対応する本文行とフレーム行のフィンガープリントが一致しない
///   行は、その行のリンクだけを除外する（結果の Map に含めない）。
///
/// frame 幅の sanity チェックまたは整列で失敗した場合は `null`（整列失敗）を返す。
/// 行ごとの除外で全ての行が
/// 除外された場合は空の Map を返す（整列自体は成功している）。
/// throw しない。純関数（副作用は前回結果の再利用のみ）。
HerdrHyperlinkAlignedLinks? resolveHerdrHyperlinkAlignedLinks({
  required Map<int, List<HerdrHyperlinkRange>> frameLinksByRow,
  required List<String?> bodyFingerprints,
  required List<String?> frameFingerprints,
  required int frameWidth,
  required int windowOffset,
}) {
  // frame 幅は sanity のみ確認する（依頼幅との一致はもう見ない）。
  // helper が実際に使った frameWidth が壊れていない（正の値である）ことだけ
  // 確認する。frameRows（0 件）の sanity は下の bodyLineCount/frameRows の
  // チェックが担う。
  if (frameWidth <= 0) return null; // frame 幅の sanity チェック

  final bodyLineCount = bodyFingerprints.length;
  final frameRows = frameFingerprints.length;
  if (bodyLineCount == 0 || frameRows == 0) return null;

  final alignment = resolveHerdrHyperlinkAlignment(
    bodyFingerprints: bodyFingerprints,
    frameFingerprints: frameFingerprints,
    windowOffset: windowOffset,
  );
  if (alignment == null) return null; // 整列失敗

  final linksByBodyLine = <int, List<HerdrHyperlinkRange>>{};
  for (final entry in frameLinksByRow.entries) {
    final frameRow = entry.key;
    if (frameRow < 0 || frameRow >= frameRows) continue;
    final bodyIndex = alignFrameRowToBodyLine(
      frameRow: frameRow,
      frameRows: frameRows,
      windowOffset: windowOffset,
      bodyLineCount: bodyLineCount,
      k: alignment.k,
    );
    if (bodyIndex == null) continue;

    // 整列後、対応する行のフィンガープリントが一致しなければ、
    // その行のリンクだけを抑制する。
    final frameFp = frameFingerprints[frameRow];
    final bodyFp = bodyFingerprints[bodyIndex];
    if (frameFp == null || bodyFp == null || frameFp != bodyFp) continue;

    (linksByBodyLine[bodyIndex] ??= <HerdrHyperlinkRange>[]).addAll(
      entry.value,
    );
  }

  return HerdrHyperlinkAlignedLinks(
    k: alignment.k,
    linksByBodyLine: linksByBodyLine,
  );
}

/// [resolveHerdrHyperlinkAlignedLinks] の結果（整列成功時）。
final class HerdrHyperlinkAlignedLinks {
  /// 採用された k。
  final int k;

  /// frame 幅の確認・整列・行ごとの除外を通過した「本文行番号 → リンク範囲」の対応。
  final Map<int, List<HerdrHyperlinkRange>> linksByBodyLine;

  const HerdrHyperlinkAlignedLinks({
    required this.k,
    required this.linksByBodyLine,
  });
}
