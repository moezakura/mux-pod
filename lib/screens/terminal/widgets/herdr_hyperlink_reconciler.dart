// Herdr OSC 8 ハイパーリンク（通常表示）: PaneHyperlinks を本文の解析済み行へ
// 重ね合わせる。
//
// [HerdrRowFingerprint] / [resolveHerdrHyperlinkAlignedLinks]（frame 幅の
// sanity チェック・整列・行ごとの抑制を合成した純関数）と
// [overlayHerdrHyperlinks] を `PaneHyperlinks` に対して結線する
// 層。純関数のみ（I/O・backend 依存なし）。
//
// スクロールモード（`TerminalMode.select`）はこの経路を使わない
// （スクロールモード中は、通常表示で取得した viewport のリンクは
// 重ねない）。呼び出し側（[AnsiTextView]）がモードで切り替える。
library;

import '../../../services/backend/domain/pane_frame_reader.dart';
import '../../../services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import '../../../services/terminal/ansi_parser.dart';
import '../session/session_models.dart' show paneHyperlinksEquals;
import 'herdr_hyperlink_overlay.dart';

/// 通常表示のリンク重ね合わせ（整列・抑制ルールの合成）。
///
/// - [bodyLines]: `AnsiDisplayModel.parsedLines()` の結果（本文の解析済み行）。
/// - [parser]: [bodyLines] を生成した `AnsiDisplayModel.parser`。実際の行の
///   重ね合わせ（[overlayHerdrHyperlinks]）へそのまま橋渡しする。
/// - [hyperlinks]: helper `hyperlinks` サブコマンド由来の取得結果。`null`
///   （未取得・設定 OFF・非 herdr backend）なら [bodyLines] をそのまま返す。
/// - [paneWidth]: 現在の計算には使わない（helper が実 pty サイズを Dart から
///   渡した値より優先して使うようになったため、frame 幅の判定は「依頼幅との
///   一致」を見なくなった）。入力定義（解析結果・リンク結果・paneWidth・
///   paneHeight）に含まれるため、[HerdrHyperlinkReconcileMemo] のメモの
///   キーには引き続き含める（[paneHeight] と同じ扱い）。
///
/// 適用する抑制ルール:
/// - frame 幅: helper が実際に使った frame 幅（[PaneHyperlinks.frameWidth]）の
///   sanity チェックのみ（`frameWidth <= 0` なら抑制）。幅の不一致（本文と
///   frame で実際の折り返しが違う場合）は行フィンガープリントの不一致として
///   次の 2 ルールが捕捉する。
/// - 整列: 多数決で本文行とフレーム行の対応（差 k）が決まらない窓は全リンクを
///   抑制する。
/// - 行フィンガープリント: 整列後、対応する本文行とフレーム行のフィンガー
///   プリントが一致しない行は、その行のリンクだけを抑制する。
///
/// throw しない。
List<ParsedLine> reconcileHerdrHyperlinks({
  required List<ParsedLine> bodyLines,
  required AnsiParser parser,
  required PaneHyperlinks? hyperlinks,
  required int paneWidth,
}) {
  if (hyperlinks == null || hyperlinks.links.isEmpty) return bodyLines;

  final bodyLineCount = bodyLines.length;
  final frameRows = hyperlinks.frameHeight;
  if (bodyLineCount == 0 || frameRows <= 0) return bodyLines;

  final bodyFingerprints = List<String?>.generate(
    bodyLineCount,
    (i) => HerdrRowFingerprint.rowFingerprint(
      bodyLines[i].segments.map((s) => s.text).join(),
    ),
    growable: false,
  );
  final frameFingerprints = List<String?>.generate(
    frameRows,
    (r) => hyperlinks.rowFingerprints[r],
    growable: false,
  );

  // PaneHyperlinks.links（url ごとにまとめられている）を、整列の入力形
  // （フレーム行番号 → その行のリンク範囲）へ組み替える。
  final frameLinksByRow = <int, List<HerdrHyperlinkRange>>{};
  for (final link in hyperlinks.links) {
    for (final range in link.ranges) {
      (frameLinksByRow[range.row] ??= <HerdrHyperlinkRange>[]).add(
        HerdrHyperlinkRange(
          startCol: range.startCol,
          endCol: range.endCol,
          url: link.url,
        ),
      );
    }
  }

  // 通常表示は Herdr のスクロール位置を動かさない。窓の位置
  // offset_from_bottom は常に 0。
  const windowOffset = 0;

  // 行フィンガープリントによる整列（多数決）と frame 幅・行ごとの抑制の合成
  // （純関数に委譲）。frame 幅は helper が実際に使った frameWidth の
  // sanity チェックのみ。
  final aligned = resolveHerdrHyperlinkAlignedLinks(
    frameLinksByRow: frameLinksByRow,
    bodyFingerprints: bodyFingerprints,
    frameFingerprints: frameFingerprints,
    frameWidth: hyperlinks.frameWidth,
    windowOffset: windowOffset,
  );
  if (aligned == null) return bodyLines; // frame 幅の sanity チェックまたは整列で失敗
  if (aligned.linksByBodyLine.isEmpty) return bodyLines; // 行ごとの除外で全行が抑制された

  return overlayHerdrHyperlinks(
    parser: parser,
    parsedLines: bodyLines,
    linksByLine: aligned.linksByBodyLine,
  );
}

/// [reconcileHerdrHyperlinks] の直近1回の呼び出し結果をメモ化する
/// （入力（本文の解析結果・リンク
/// 結果・paneWidth・paneHeight）が同じなら前回の結果をそのまま返す）。
///
/// [AnsiTextViewState] が1インスタンスを保持し、`build()` ごとに [reconcile]
/// を呼ぶ想定。呼び出し元を1つに限定するため、直近1回分だけを覚える
/// （不特定多数の入力組を溜め込まない）。
///
/// 呼び出し規約は [reconcileHerdrHyperlinks] と同じ（throw しない・sync・
/// 副作用はこのメモの更新のみ）。[bodyLines] は identity、[hyperlinks] は
/// identity または [paneHyperlinksEquals] のいずれかが一致すれば、前回と
/// 同じ結果（同一インスタンス）を返す。
class HerdrHyperlinkReconcileMemo {
  List<ParsedLine>? _lastBodyLines;
  PaneHyperlinks? _lastHyperlinks;
  int? _lastPaneWidth;
  int? _lastPaneHeight;
  List<ParsedLine>? _lastResult;

  /// [reconcileHerdrHyperlinks] のメモ化された呼び出し。
  ///
  /// [paneWidth]・[paneHeight] は現在の [reconcileHerdrHyperlinks] の計算
  /// には使わないが（[paneWidth] は frame 幅の判定から外れた。[paneHeight]
  /// はもともと未使用）、入力定義（解析結果・リンク結果・
  /// paneWidth・paneHeight）に含まれるため、メモのキーには含める（将来
  /// どちらかが計算に関わる変更が入っても、キャッシュキーの見直しを
  /// 忘れない防御）。
  List<ParsedLine> reconcile({
    required List<ParsedLine> bodyLines,
    required AnsiParser parser,
    required PaneHyperlinks? hyperlinks,
    required int paneWidth,
    required int paneHeight,
  }) {
    final lastResult = _lastResult;
    if (lastResult != null &&
        identical(_lastBodyLines, bodyLines) &&
        _lastPaneWidth == paneWidth &&
        _lastPaneHeight == paneHeight &&
        (identical(_lastHyperlinks, hyperlinks) ||
            paneHyperlinksEquals(_lastHyperlinks, hyperlinks))) {
      return lastResult;
    }

    final result = reconcileHerdrHyperlinks(
      bodyLines: bodyLines,
      parser: parser,
      hyperlinks: hyperlinks,
      paneWidth: paneWidth,
    );

    _lastBodyLines = bodyLines;
    _lastHyperlinks = hyperlinks;
    _lastPaneWidth = paneWidth;
    _lastPaneHeight = paneHeight;
    _lastResult = result;
    return result;
  }
}
