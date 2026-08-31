/// ペイン内容読み取りの共通 domain。
///
/// tmux（`TmuxPaneContentReader`）と herdr（`HerdrPaneContentReader`）の
/// backend 差異（カーソル位置・モード・サイズの有無）を吸収し、
/// 表示コア（`AnsiTextView` / ポーリングループ）が同じコードで
/// 両 backend を扱えるようにする。
library;

import 'pane_frame_reader.dart';
import 'pane_read.dart';

/// ペインの文字セル単位の幾何情報。
///
/// 不明な場合は null（従来の `width=0` による「欠損値か実値か」の曖昧さを
/// 型で排除する・バグ1 根本対応）。
class PaneGeometry {
  /// 文字幅（文字セル数）。
  final int width;

  /// 文字高さ（文字セル数）。
  final int height;

  const PaneGeometry({required this.width, required this.height});

  @override
  String toString() => 'PaneGeometry(${width}x$height)';
}

/// ペイン内容読み取り結果の共通 domain スナップショット。
///
/// herdr にはカーソル位置・モードが無いため、それらは 0 / 空文字のまま
/// （フォールバック）で返す。サイズは不明なら [geometry] を null にする
/// （表示側は既定 80x24 へフォールバックする）。
class MultiplexerPaneSnapshot {
  /// 表示用の生テキスト（ANSI エスケープ付きの場合あり）。
  final String content;

  /// ペインの文字セル単位のサイズ（不明なら null）。
  final PaneGeometry? geometry;

  /// カーソル X（0-based。不明なら 0）。
  final int cursorX;

  /// カーソル Y（0-based。不明なら 0）。
  final int cursorY;

  /// モード文字列（tmux copy-mode 等。無い backend は空文字）。
  final String paneMode;

  /// 内容が ANSI エスケープを含むかどうか。
  final bool hasAnsi;

  /// herdr カーソル情報（caret）。他 backend・未取得時は null
  /// （従来の cursorX / cursorY 契約へフォールバックする）。
  final PaneCaret? caret;

  const MultiplexerPaneSnapshot({
    required this.content,
    this.geometry,
    this.cursorX = 0,
    this.cursorY = 0,
    this.paneMode = '',
    this.hasAnsi = false,
    this.caret,
  });

  /// 後方互換: 文字幅（不明なら 0）。
  ///
  /// 新コードは [geometry] を使う。不明を 0 で表す旧形式の互換用。
  int get width => geometry?.width ?? 0;

  /// 後方互換: 文字高さ（不明なら 0）。
  int get height => geometry?.height ?? 0;

  @override
  String toString() =>
      'MultiplexerPaneSnapshot(${geometry?.toString() ?? 'unknown'}, '
      '${content.length} chars, cursor=$cursorX,$cursorY, mode="$paneMode", '
      'ansi: $hasAnsi)';
}

/// ペイン内容の読み取り抽象。
///
/// 表示コアはこの抽象だけに依存する。失敗時は例外
/// （`TmuxCommandException` / `HerdrCommandException`）を投げる。
abstract interface class PaneContentReader {
  /// [request] に基づいてペイン内容を読み取る。
  ///
  /// [PaneReadRequest.purpose] でライブ / スクロールバックの目的を明示し、
  /// [PaneReadRequest.maxLines] で取得上限を指定する。行数の符号・大小による
  /// 暗黙の意味判定は行わない（バグ4 根本対応）。
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request);
}
