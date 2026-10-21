// Herdr OSC 8 ハイパーリンク（スクロールモード）: ScrollbackLinkCache を本文の
// 解析済み行へ重ね合わせる。
//
// [overlayHerdrHyperlinks]（変更なしで再利用）を
// `ScrollbackLinkCache` に対して結線する層。
//
// 世代ガード: `cache.identity`/`cache.generation`（ScrollbackLinkCache は
// スナップショットの identity を identity オブジェクトと generation の両方で
// 保持する）が両方とも [currentSnapshotIdentity] と一致するときだけ重ねる。
// identity は `==`（値の等価性）で比較する（generation だけの比較だと、
// controller の作り直しや再接続の後に番号が偶然一致して衝突する余地が
// 残るため）。identity の実体（`HerdrTargetIdentity`）は呼び出しのたびに
// 新しい record インスタンスが作られるため、`identical` で比較すると本番
// では常に不一致になりリンクが一度も表示されない。
// `HerdrController.isCurrentIdentity` と同じ「値の等価性」基準に
// 揃える。一致しなければ（スナップショットが差し替わった後、古い世代の
// 結果しかキャッシュに無い等）本文をそのまま返す
// （`TerminalScrollFollowController.currentSnapshotIdentity` のコメント
// 「スナップショット差し替え後の結果を表示に混ぜない」と同じ意図）。
//
// 通常表示（herdr_hyperlink_reconciler.dart）はこの経路を使わない
// （スクロールモード中は通常表示で取得した viewport のリンクを重ねない、の
// 逆）。呼び出し側（[AnsiTextView]）がモードで切り替える。
library;

import '../../../services/herdr/hyperlink/scrollback_link_cache.dart';
import '../../../services/terminal/ansi_parser.dart';
import 'herdr_hyperlink_overlay.dart';

/// スクロールモードのリンク重ね合わせ。
///
/// - [bodyLines]: `AnsiDisplayModel.parsedLines()` の結果（select モードは
///   スクロールモードに入った時点で固定された本文）。
/// - [parser]: [bodyLines] を生成した `AnsiDisplayModel.parser`。
/// - [cache]: `null` なら重ね合わせない（スクロールモード外・機能 OFF・
///   未取得等）。
/// - [currentSnapshotIdentity]: `null`、または `cache.identity`/
///   `cache.generation` のどちらかが一致しなければ重ね合わせない。
///
/// throw しない。
List<ParsedLine> overlayScrollbackHyperlinks({
  required List<ParsedLine> bodyLines,
  required AnsiParser parser,
  required ScrollbackLinkCache? cache,
  required ({Object? identity, int generation})? currentSnapshotIdentity,
}) {
  if (cache == null) return bodyLines;
  final cacheGeneration = cache.generation;
  if (cacheGeneration == null) return bodyLines;
  if (currentSnapshotIdentity == null) return bodyLines; // 世代ガード
  if (cache.identity != currentSnapshotIdentity.identity ||
      cacheGeneration != currentSnapshotIdentity.generation) {
    // スナップショット差し替え後、または generation を跨がない
    // 再接続（identity だけが変わる場合）。
    return bodyLines;
  }

  final linksByLine = cache.linksByBodyLine;
  if (linksByLine.isEmpty) return bodyLines;

  return overlayHerdrHyperlinks(
    parser: parser,
    parsedLines: bodyLines,
    linksByLine: linksByLine,
  );
}

/// [overlayScrollbackHyperlinks] の直近1回の呼び出し結果をメモ化する
/// （`HerdrHyperlinkReconcileMemo` の select モード版）。
///
/// `(cache.identity, cache.generation, cache.revision,
/// currentSnapshotIdentity.identity, currentSnapshotIdentity.generation)`
/// をメモ化キーに使う（`generation` だけでは、同一 generation 内で新しく
/// 取得した窓（[ScrollbackLinkCache] は generation を変えずに内容を更新
/// する設計）を見逃すため。identity も含めるのは世代ガードと同じ理由。
/// [ScrollbackLinkCache.revision] のドキュメント参照）。
///
/// [AnsiTextViewState] が1インスタンスを保持し、`build()` ごとに [overlay]
/// を呼ぶ想定。呼び出し規約は [overlayScrollbackHyperlinks] と同じ（throw
/// しない・sync・副作用はこのメモの更新のみ）。
class HerdrScrollbackHyperlinkMemo {
  List<ParsedLine>? _lastBodyLines;
  Object? _lastIdentity;
  int? _lastGeneration;
  int? _lastRevision;
  Object? _lastCurrentIdentity;
  int? _lastCurrentGeneration;
  List<ParsedLine>? _lastResult;

  /// [overlayScrollbackHyperlinks] のメモ化された呼び出し。
  List<ParsedLine> overlay({
    required List<ParsedLine> bodyLines,
    required AnsiParser parser,
    required ScrollbackLinkCache? cache,
    required ({Object? identity, int generation})? currentSnapshotIdentity,
  }) {
    final identity = cache?.identity;
    final generation = cache?.generation;
    final revision = cache?.revision;
    final currentIdentity = currentSnapshotIdentity?.identity;
    final currentGeneration = currentSnapshotIdentity?.generation;

    final lastResult = _lastResult;
    if (lastResult != null &&
        identical(_lastBodyLines, bodyLines) &&
        _lastIdentity == identity &&
        _lastGeneration == generation &&
        _lastRevision == revision &&
        _lastCurrentIdentity == currentIdentity &&
        _lastCurrentGeneration == currentGeneration) {
      return lastResult;
    }

    final result = overlayScrollbackHyperlinks(
      bodyLines: bodyLines,
      parser: parser,
      cache: cache,
      currentSnapshotIdentity: currentSnapshotIdentity,
    );

    _lastBodyLines = bodyLines;
    _lastIdentity = identity;
    _lastGeneration = generation;
    _lastRevision = revision;
    _lastCurrentIdentity = currentIdentity;
    _lastCurrentGeneration = currentGeneration;
    _lastResult = result;
    return result;
  }
}
