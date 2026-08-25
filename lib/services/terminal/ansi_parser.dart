import 'package:flutter/material.dart';

import 'terminal_font_styles.dart';

/// ANSIテキストスタイル
class AnsiStyle {
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool dim;
  final bool inverse;

  const AnsiStyle({
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.dim = false,
    this.inverse = false,
  });

  AnsiStyle copyWith({
    Color? foreground,
    Color? background,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? dim,
    bool? inverse,
    bool clearForeground = false,
    bool clearBackground = false,
  }) {
    return AnsiStyle(
      foreground: clearForeground ? null : (foreground ?? this.foreground),
      background: clearBackground ? null : (background ?? this.background),
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      dim: dim ?? this.dim,
      inverse: inverse ?? this.inverse,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnsiStyle &&
          foreground == other.foreground &&
          background == other.background &&
          bold == other.bold &&
          italic == other.italic &&
          underline == other.underline &&
          strikethrough == other.strikethrough &&
          dim == other.dim &&
          inverse == other.inverse;

  @override
  int get hashCode => Object.hash(
    foreground,
    background,
    bold,
    italic,
    underline,
    strikethrough,
    dim,
    inverse,
  );

  static const AnsiStyle defaultStyle = AnsiStyle();
}

/// ANSIテキストセグメント
class AnsiSegment {
  final String text;
  final AnsiStyle style;

  const AnsiSegment(this.text, this.style);
}

/// パースされた行データ
class ParsedLine {
  /// この行のセグメントリスト
  final List<AnsiSegment> segments;

  /// この行の終了時のスタイル（次の行に引き継ぐ）
  final AnsiStyle endStyle;

  const ParsedLine({required this.segments, required this.endStyle});

  /// 空行かどうか
  bool get isEmpty => segments.isEmpty || segments.every((s) => s.text.isEmpty);
}

/// 行→TextSpan の描画キャッシュエントリ（[AnsiParser] 内部で使用）。
class _LineSpan {
  final TextSpan span;
  final double fontSize;
  final String fontFamily;
  const _LineSpan(this.span, this.fontSize, this.fontFamily);
}

/// ANSIエスケープシーケンスパーサー
///
/// capture-pane -e の出力（ANSIカラー付きテキスト）を
/// TextSpanに変換するためのパーサー。
class AnsiParser {
  /// SGR (Select Graphic Rendition) パターン: ESC[...m
  static final _sgrRegex = RegExp(r'\x1b\[([0-9;]*)m');

  /// 標準8色（通常）
  static const List<Color> standardColors = [
    Color(0xFF000000), // 0: Black
    Color(0xFFCD3131), // 1: Red
    Color(0xFF0DBC79), // 2: Green
    Color(0xFFE5E510), // 3: Yellow
    Color(0xFF2472C8), // 4: Blue
    Color(0xFFBC3FBC), // 5: Magenta
    Color(0xFF11A8CD), // 6: Cyan
    Color(0xFFE5E5E5), // 7: White
  ];

  /// 標準8色（明るい）
  static const List<Color> brightColors = [
    Color(0xFF666666), // 8: Bright Black
    Color(0xFFF14C4C), // 9: Bright Red
    Color(0xFF23D18B), // 10: Bright Green
    Color(0xFFF5F543), // 11: Bright Yellow
    Color(0xFF3B8EEA), // 12: Bright Blue
    Color(0xFFD670D6), // 13: Bright Magenta
    Color(0xFF29B8DB), // 14: Bright Cyan
    Color(0xFFFFFFFF), // 15: Bright White
  ];

  /// デフォルトの前景色
  final Color defaultForeground;

  /// デフォルトの背景色
  final Color defaultBackground;

  AnsiParser({
    this.defaultForeground = const Color(0xFFD4D4D4),
    this.defaultBackground = const Color(0xFF1E1E1E),
  });

  /// インクリメンタルパース用キャッシュ: (開始スタイル, 行テキスト) → 解析済み行。
  /// 行の出力は (開始スタイル, テキスト) のみに依存するので、位置が変わっても
  /// （出力が流れて全行が上にシフトしても）同一キーで再利用でき、再パースは
  /// 末尾の新規行だけになる。同じ ParsedLine インスタンスを返すため
  /// [_spanCache]（弱参照キー）も同時にヒットする。
  Map<(AnsiStyle, String), ParsedLine> _lineCache = const {};

  /// 行→TextSpan の描画キャッシュ（弱参照キー = ParsedLine）。
  /// ParsedLineがGCされればエントリも消えるためリークしない。
  /// スクロールや再ビルドで可視行のTextSpanを毎フレーム作り直すのを防ぐ。
  final Expando<_LineSpan> _spanCache = Expando<_LineSpan>('lineSpan');

  /// ANSIテキストをセグメントに分解
  List<AnsiSegment> parse(String input) {
    final segments = <AnsiSegment>[];
    var currentStyle = AnsiStyle.defaultStyle;
    var lastEnd = 0;

    for (final match in _sgrRegex.allMatches(input)) {
      // マッチ前のテキストを追加
      if (match.start > lastEnd) {
        final text = input.substring(lastEnd, match.start);
        if (text.isNotEmpty) {
          segments.add(AnsiSegment(text, currentStyle));
        }
      }

      // SGRパラメータを解析してスタイルを更新
      final params = match.group(1) ?? '';
      currentStyle = _parseSgr(params, currentStyle);
      lastEnd = match.end;
    }

    // 残りのテキストを追加
    if (lastEnd < input.length) {
      final text = input.substring(lastEnd);
      if (text.isNotEmpty) {
        segments.add(AnsiSegment(text, currentStyle));
      }
    }

    return segments;
  }

  /// SGRパラメータを解析してスタイルを更新
  AnsiStyle _parseSgr(String params, AnsiStyle current) {
    if (params.isEmpty) {
      return AnsiStyle.defaultStyle;
    }

    final codes = params.split(';').map((s) => int.tryParse(s) ?? 0).toList();
    var style = current;
    var i = 0;

    while (i < codes.length) {
      final code = codes[i];

      switch (code) {
        case 0: // リセット
          style = AnsiStyle.defaultStyle;
          break;
        case 1: // 太字
          style = style.copyWith(bold: true);
          break;
        case 2: // 薄暗い
          style = style.copyWith(dim: true);
          break;
        case 3: // イタリック
          style = style.copyWith(italic: true);
          break;
        case 4: // 下線
          style = style.copyWith(underline: true);
          break;
        case 7: // 反転
          style = style.copyWith(inverse: true);
          break;
        case 9: // 取り消し線
          style = style.copyWith(strikethrough: true);
          break;
        case 21: // 太字解除 (一部の端末)
        case 22: // 太字・薄暗さ解除
          style = style.copyWith(bold: false, dim: false);
          break;
        case 23: // イタリック解除
          style = style.copyWith(italic: false);
          break;
        case 24: // 下線解除
          style = style.copyWith(underline: false);
          break;
        case 27: // 反転解除
          style = style.copyWith(inverse: false);
          break;
        case 29: // 取り消し線解除
          style = style.copyWith(strikethrough: false);
          break;
        case 30:
        case 31:
        case 32:
        case 33:
        case 34:
        case 35:
        case 36:
        case 37:
          // 標準前景色 (30-37)
          style = style.copyWith(foreground: standardColors[code - 30]);
          break;
        case 38:
          // 拡張前景色
          if (i + 1 < codes.length) {
            if (codes[i + 1] == 5 && i + 2 < codes.length) {
              // 256色モード: 38;5;n
              style = style.copyWith(foreground: _get256Color(codes[i + 2]));
              i += 2;
            } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
              // 24ビットカラー: 38;2;r;g;b
              style = style.copyWith(
                foreground: Color.fromARGB(
                  255,
                  codes[i + 2].clamp(0, 255),
                  codes[i + 3].clamp(0, 255),
                  codes[i + 4].clamp(0, 255),
                ),
              );
              i += 4;
            }
          }
          break;
        case 39: // デフォルト前景色
          style = style.copyWith(clearForeground: true);
          break;
        case 40:
        case 41:
        case 42:
        case 43:
        case 44:
        case 45:
        case 46:
        case 47:
          // 標準背景色 (40-47)
          style = style.copyWith(background: standardColors[code - 40]);
          break;
        case 48:
          // 拡張背景色
          if (i + 1 < codes.length) {
            if (codes[i + 1] == 5 && i + 2 < codes.length) {
              // 256色モード: 48;5;n
              style = style.copyWith(background: _get256Color(codes[i + 2]));
              i += 2;
            } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
              // 24ビットカラー: 48;2;r;g;b
              style = style.copyWith(
                background: Color.fromARGB(
                  255,
                  codes[i + 2].clamp(0, 255),
                  codes[i + 3].clamp(0, 255),
                  codes[i + 4].clamp(0, 255),
                ),
              );
              i += 4;
            }
          }
          break;
        case 49: // デフォルト背景色
          style = style.copyWith(clearBackground: true);
          break;
        case 90:
        case 91:
        case 92:
        case 93:
        case 94:
        case 95:
        case 96:
        case 97:
          // 明るい前景色 (90-97)
          style = style.copyWith(foreground: brightColors[code - 90]);
          break;
        case 100:
        case 101:
        case 102:
        case 103:
        case 104:
        case 105:
        case 106:
        case 107:
          // 明るい背景色 (100-107)
          style = style.copyWith(background: brightColors[code - 100]);
          break;
      }
      i++;
    }

    return style;
  }

  /// 256色パレットから色を取得
  Color _get256Color(int index) {
    if (index < 0 || index > 255) {
      return defaultForeground;
    }

    // 0-7: 標準色
    if (index < 8) {
      return standardColors[index];
    }

    // 8-15: 明るい色
    if (index < 16) {
      return brightColors[index - 8];
    }

    // 16-231: 6x6x6 カラーキューブ
    if (index < 232) {
      final n = index - 16;
      final r = (n ~/ 36) % 6;
      final g = (n ~/ 6) % 6;
      final b = n % 6;
      return Color.fromARGB(
        255,
        r > 0 ? (r * 40 + 55) : 0,
        g > 0 ? (g * 40 + 55) : 0,
        b > 0 ? (b * 40 + 55) : 0,
      );
    }

    // 232-255: グレースケール
    final gray = (index - 232) * 10 + 8;
    return Color.fromARGB(255, gray, gray, gray);
  }

  /// セグメントをTextSpanに変換
  TextSpan toTextSpan(
    List<AnsiSegment> segments, {
    required double fontSize,
    required String fontFamily,
  }) {
    return TextSpan(
      children: segments
          .map(
            (segment) => _segmentToTextSpan(
              segment,
              fontSize: fontSize,
              fontFamily: fontFamily,
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
  }) {
    final style = segment.style;
    final (:foreground, :background, :paintBackground) = resolvePaintColors(
      style,
    );
    var fg = foreground;
    final bg = background;

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
        ]),
      ),
    );
  }

  /// ANSIテキストを直接TextSpanに変換
  TextSpan parseToTextSpan(
    String input, {
    required double fontSize,
    required String fontFamily,
  }) {
    final segments = parse(input);
    return toTextSpan(segments, fontSize: fontSize, fontFamily: fontFamily);
  }

  /// 行単位でパース（仮想スクロール用）
  ///
  /// 各行を個別にパースし、スタイルを次の行に引き継ぐ。
  /// 返り値の[ParsedLine]リストは、仮想スクロールで行単位にレンダリングするために使用。
  List<ParsedLine> parseLines(String input) {
    // PTY 経由では \r\n や行末の \r が混入するため、行分割前に正規化する
    // （\n\n 由来の空行はここでは削除せず、実データの空行として保持）。
    final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '');
    final lines = normalized.split('\n');
    final prev = _lineCache;
    final next = <(AnsiStyle, String), ParsedLine>{};
    final parsed = <ParsedLine>[];
    var currentStyle = AnsiStyle.defaultStyle;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final key = (currentStyle, line);
      // (開始スタイル, テキスト) が一致すれば位置に関係なく再利用（再パース回避）。
      var pl = next[key] ?? prev[key];
      if (pl == null) {
        final r = _parseLineWithStyle(line, currentStyle);
        pl = ParsedLine(segments: r.segments, endStyle: r.endStyle);
      }
      parsed.add(pl);
      next[key] = pl;
      currentStyle = pl.endStyle;
    }

    _lineCache = next;
    return parsed;
  }

  /// 1行をパースし、セグメントと終了スタイルを返す
  ({List<AnsiSegment> segments, AnsiStyle endStyle}) _parseLineWithStyle(
    String line,
    AnsiStyle startStyle,
  ) {
    final segments = <AnsiSegment>[];
    var currentStyle = startStyle;
    var lastEnd = 0;

    for (final match in _sgrRegex.allMatches(line)) {
      // マッチ前のテキストを追加
      if (match.start > lastEnd) {
        final text = line.substring(lastEnd, match.start);
        if (text.isNotEmpty) {
          segments.add(AnsiSegment(text, currentStyle));
        }
      }

      // SGRパラメータを解析してスタイルを更新
      final params = match.group(1) ?? '';
      currentStyle = _parseSgr(params, currentStyle);
      lastEnd = match.end;
    }

    // 残りのテキストを追加
    if (lastEnd < line.length) {
      final text = line.substring(lastEnd);
      if (text.isNotEmpty) {
        segments.add(AnsiSegment(text, currentStyle));
      }
    }

    return (segments: segments, endStyle: currentStyle);
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
  TextSpan lineToTextSpan(
    ParsedLine line, {
    required double fontSize,
    required String fontFamily,
  }) {
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
  /// - [caret]: 挿入するインライン要素。null の場合はキャッシュ済みの通常行スパンを返す。
  TextSpan lineToTextSpanWithCaret(
    ParsedLine line, {
    required double fontSize,
    required String fontFamily,
    required int caretCharOffset,
    required int padColumns,
    InlineSpan? caret,
  }) {
    if (caret == null) {
      return lineToTextSpan(line, fontSize: fontSize, fontFamily: fontFamily);
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
              AnsiSegment(segment.text.substring(0, local), segment.style),
              fontSize: fontSize,
              fontFamily: fontFamily,
            ),
          );
        }
        spans.add(caret);
        if (local < segLen) {
          spans.add(
            _segmentToTextSpan(
              AnsiSegment(segment.text.substring(local), segment.style),
              fontSize: fontSize,
              fontFamily: fontFamily,
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
