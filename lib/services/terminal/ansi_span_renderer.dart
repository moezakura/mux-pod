import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_muxpod/theme/terminal_colors.dart';

import 'ansi_models.dart';
import 'terminal_font_styles.dart';

/// 行→TextSpan の描画キャッシュエントリ（[AnsiSpanRenderer] 内部で使用）。
class _LineSpan {
  final TextSpan span;
  final double fontSize;
  final String fontFamily;
  const _LineSpan(this.span, this.fontSize, this.fontFamily);
}

/// リンク recognizer 解決器: URL → タップ recognizer。
///
/// null を返した URL は recognizer 無し（装飾のみ・タップ不可 — 非識別 URL
/// の仕様）。recognizer の所有・dispose は解決器を渡した呼び出し側
/// （行ウィジェットの State）の責務であり、renderer / スパンキャッシュは
/// recognizer を一切保持しない（resolver 付き構築はキャッシュ迂回）。
typedef LinkTapResolver = TapGestureRecognizer? Function(String url);

/// ParsedLine / セグメント列から TextSpan を構築する。
///
/// 行→TextSpan の弱参照キャッシュ（[_spanCache]）を所有する。
/// キャッシュのキーは [ParsedLine] インスタンスの同一性に依存するため、
/// [AnsiLineParser] が生成・再利用したインスタンスをそのまま渡すこと
/// （ファサードが委譲時に assert で検証する）。
class AnsiSpanRenderer {
  /// デフォルトの前景色
  final Color defaultForeground;

  /// デフォルトの背景色
  final Color defaultBackground;

  AnsiSpanRenderer({
    this.defaultForeground = const Color(0xFFD4D4D4),
    this.defaultBackground = const Color(0xFF1E1E1E),
  });

  /// 行→TextSpan の描画キャッシュ（弱参照キー = ParsedLine）。
  /// ParsedLineがGCされればエントリも消えるためリークしない。
  /// スクロールや再ビルドで可視行のTextSpanを毎フレーム作り直すのを防ぐ。
  final Expando<_LineSpan> _spanCache = Expando<_LineSpan>('lineSpan');

  /// セグメントをTextSpanに変換
  TextSpan toTextSpan(
    List<AnsiSegment> segments, {
    required double fontSize,
    required String fontFamily,
    LinkTapResolver? linkTapResolver,
  }) {
    return TextSpan(
      children: segments
          .map(
            (segment) => _segmentToTextSpan(
              segment,
              fontSize: fontSize,
              fontFamily: fontFamily,
              linkTapResolver: linkTapResolver,
            ),
          )
          .toList(),
    );
  }

  /// 1セグメントを描画スタイル適用済みのTextSpanに変換
  ///
  /// 背景色は opaque（不透明）で常時設定する（HYP-4 opaque 化）。これは
  /// 「途中にデフォルト区間を持ち、かつ行末まで色が埋まって末尾リセットが無い」
  /// 行（endStyle=色 → 全幅レイヤー有色）で、途中デフォルト span が透明のまま
  /// 下層の色を透かすのを防ぐ保険。デフォルト背景 span は
  /// defaultBackground（= 親コンテナ背景と同一）を不透明塗りするため、
  /// 通常描画の見た目は変わらない。inverse・実色背景も従来どおり塗られる。
  /// [resolvePaintColors] の paintBackground 判定は行背景レイヤー
  /// （[effectiveLineBackgroundColor]）用に維持する。
  TextSpan _segmentToTextSpan(
    AnsiSegment segment, {
    required double fontSize,
    required String fontFamily,
    LinkTapResolver? linkTapResolver,
  }) {
    final style = segment.style;
    final url = segment.url;
    final (:foreground, :background, :paintBackground) = resolvePaintColors(
      style,
    );
    var fg = foreground;
    final bg = background;

    // リンク色: SGR で明示前景色がない場合のみ適用（SGR 色を壊さない）。
    // 適用位置は resolvePaintColors 後・dim 前 に pin（テスト期待値で固定）。
    if (url != null && style.foreground == null) {
      fg = TerminalColors.brightBlue;
    }

    // 薄暗い
    if (style.dim) {
      fg = fg.withValues(alpha: 0.5);
    }

    // 反転時のスペースは背景色が描画されないことがあるため、No-Break Spaceに置換
    String text = segment.text;
    if (style.inverse) {
      text = text.replaceAll(' ', '\u00A0');
    }

    return TextSpan(
      text: text,
      style: TerminalFontStyles.getTextStyle(
        fontFamily,
        fontSize: fontSize,
        color: fg,
        backgroundColor: bg,
        fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (style.underline) TextDecoration.underline,
          if (style.strikethrough) TextDecoration.lineThrough,
          // リンク下線は SGR 装飾に「追加合成」する（上書きしない）。
          if (url != null) TextDecoration.underline,
        ]),
      ),
      // recognizer は resolver があるときのみ付与（resolver == null の
      // キャッシュ済み span に recognizer が入る経路は存在しない）。
      recognizer: url != null && linkTapResolver != null
          ? linkTapResolver(url)
          : null,
    );
  }

  /// セグメント/行スタイルから描画用の前景色・背景色と「背景を描くか」を決定する。
  ///
  /// inverse 時は前背景を入れ替える。`paintBackground`（`inverse || 背景≠default`）
  /// は行背景レイヤー（[effectiveLineBackgroundColor]）の要否判定に使う単一ソース
  /// （R3）であり、[_segmentToTextSpan] 側は opaque 化により背景色を常時設定する
  /// （HYP-4 opaque）。
  ({Color foreground, Color background, bool paintBackground})
  resolvePaintColors(AnsiStyle style) {
    var fg = style.foreground ?? defaultForeground;
    var bg = style.background ?? defaultBackground;
    if (style.inverse) {
      final temp = fg;
      fg = bg;
      bg = temp;
    }
    return (
      foreground: fg,
      background: bg,
      paintBackground: style.inverse || bg != defaultBackground,
    );
  }

  /// 行全体の有効背景色（行末まで延長・空行背景用）を返す。
  ///
  /// tmux capture-pane は「デフォルト背景の末尾空セル」を出力せず、行が有色で
  /// 終わる場合に合成 `\x1b[49m` を付加する（skeptic ライブ実験・EV-LOG-006）。
  /// したがって行末セルの真のスタイルは「行内最後の SGR 適用後」= [ParsedLine.endStyle]
  /// であり、非空行も endStyle から導出する（旧「最終セグメントと同じ」前提は FALSE）。
  ///
  /// 例外: 最終セグメントが**背景付きで空白で終わる**行（例: アプリが明示的に書いた
  /// 色付きスペース列 EV-LOG-006 型）は、その空白が実在の色付きセルであり、実機の
  /// Flutter は span 末尾の空白背景を描画しない（EV-LOG-003 before: blue x=8..158 で
  /// 終端）ため、最終セグメント色で全幅レイヤーを残す（PR#98 の「行末まで色埋め」を
  /// 回帰させない）。末尾空白でない最終セグメントの行（S1/S3/S4）は余白=endStyle。
  ///
  /// デフォルト背景と等しい場合は null（背景レイヤー不要）を返す。
  Color? effectiveLineBackgroundColor(ParsedLine line) {
    if (line.segments.isNotEmpty) {
      final last = line.segments.last;
      final lastResolved = resolvePaintColors(last.style);
      // 最終セグメントが背景付き＆末尾空白 → 実色スペース列（EV-LOG-006 型）を最優先
      if (lastResolved.paintBackground && _endsWithWhitespace(last.text)) {
        return lastResolved.background;
      }
    }
    final endResolved = resolvePaintColors(line.endStyle);
    return endResolved.paintBackground ? endResolved.background : null;
  }

  /// テキストが空白文字で終わるか（全角空白・タブも含む）。
  static bool _endsWithWhitespace(String text) {
    if (text.isEmpty) return false;
    final lastRun = text.codeUnits.last;
    return lastRun == 0x20 ||
        lastRun == 0x09 ||
        lastRun == 0x00A0 ||
        lastRun == 0x3000;
  }

  /// ParsedLineをTextSpanに変換
  ///
  /// [linkTapResolver] が null の場合はキャッシュ経路（既存規約どおり同一
  /// ParsedLine → 同一 TextSpan）。非 null の場合は recognizer 付き span を
  /// 都度構築し、スパンキャッシュを**読みも書きもしない**（recognizer を
  /// キャッシュ済み span の使い回しにしないため・設計 D5）。装飾（下線・色）
  /// は [ParsedLine] から決定論的に導出されるため、resolver の有無で
  /// 見た目が変わることはない。
  TextSpan lineToTextSpan(
    ParsedLine line, {
    required double fontSize,
    required String fontFamily,
    LinkTapResolver? linkTapResolver,
  }) {
    if (linkTapResolver != null) {
      return toTextSpan(
        line.segments,
        fontSize: fontSize,
        fontFamily: fontFamily,
        linkTapResolver: linkTapResolver,
      );
    }
    final cached = _spanCache[line];
    if (cached != null &&
        cached.fontSize == fontSize &&
        cached.fontFamily == fontFamily) {
      return cached.span;
    }
    final span = toTextSpan(
      line.segments,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
    _spanCache[line] = _LineSpan(span, fontSize, fontFamily);
    return span;
  }

  /// キャレット（任意のインライン要素）を指定文字位置に直接挿入した行スパンを構築する。
  ///
  /// テキストレイアウト中の正確な位置にキャレットを「合成（Stack+Positioned）」
  /// せず直接埋め込むための API（Issue #70 根本対応）。
  ///
  /// - [caretCharOffset]: キャレットを挿入するコードユニットオフセット。
  ///   セグメント境界・行末・空行のいずれでもよい（クランプされる）。
  /// - [padColumns]: 行テキスト終端よりさらに右のカラムにキャレットを置く場合の
  ///   埋めセル数（No-Break Space で埋める）。
  /// - [caret]: 挿入するインライン要素。null の場合は [linkTapResolver] を
  ///   透過した通常行スパンを返す（blink off 相のリンクタップ対応・H2）。
  /// - [linkTapResolver]: リンク断片に recognizer を注入する解決器。
  ///   キャレットの substring 分割でリンク断片が両断片に分かれても url は
  ///   引き継がれる。キャレット行はスパンキャッシュ対象外のため
  ///   キャッシュ迂回の考慮は不要。
  TextSpan lineToTextSpanWithCaret(
    ParsedLine line, {
    required double fontSize,
    required String fontFamily,
    required int caretCharOffset,
    required int padColumns,
    InlineSpan? caret,
    LinkTapResolver? linkTapResolver,
  }) {
    if (caret == null) {
      // blink off 相（H2）: 通常行スパン経路にも resolver を透過し、
      // 点滅の両相でリンクタップが成立するようにする。
      return lineToTextSpan(
        line,
        fontSize: fontSize,
        fontFamily: fontFamily,
        linkTapResolver: linkTapResolver,
      );
    }

    final spans = <InlineSpan>[];
    var consumed = 0;
    var inserted = false;

    for (final segment in line.segments) {
      final segLen = segment.text.length;
      if (!inserted && caretCharOffset <= consumed + segLen) {
        final local = (caretCharOffset - consumed).clamp(0, segLen);
        if (local > 0) {
          spans.add(
            _segmentToTextSpan(
              AnsiSegment(
                segment.text.substring(0, local),
                segment.style,
                // キャレット分割でも url を落とさない（リンク断片の継続）。
                url: segment.url,
              ),
              fontSize: fontSize,
              fontFamily: fontFamily,
              linkTapResolver: linkTapResolver,
            ),
          );
        }
        spans.add(caret);
        if (local < segLen) {
          spans.add(
            _segmentToTextSpan(
              AnsiSegment(
                segment.text.substring(local),
                segment.style,
                url: segment.url,
              ),
              fontSize: fontSize,
              fontFamily: fontFamily,
              linkTapResolver: linkTapResolver,
            ),
          );
        }
        inserted = true;
      } else {
        spans.add(
          _segmentToTextSpan(
            segment,
            fontSize: fontSize,
            fontFamily: fontFamily,
            linkTapResolver: linkTapResolver,
          ),
        );
      }
      consumed += segLen;
    }

    if (!inserted) {
      // キャレットが行テキスト終端より先にある場合: 埋めセルで位置を再現してから挿入
      if (padColumns > 0) {
        spans.add(TextSpan(text: '\u00A0' * padColumns));
      }
      spans.add(caret);
    }

    return TextSpan(children: spans);
  }
}
