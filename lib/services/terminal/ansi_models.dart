import 'package:flutter/material.dart';

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

  /// OSC 8 ハイパーリンクの URL。null はリンク外。
  ///
  /// AnsiStyle には持たせない: AnsiStyle の ==/hashCode は装飾属性のみを
  /// 対象とする値オブジェクト等価性であり、URL を混入させるとスタイル
  /// 等価性の意味論が変わるため（設計 D3）。URL 状態は行キャッシュキーの
  /// 独立した要素 (開始スタイル, 開始 URL 状態, 行テキスト) として扱う
  /// （🤝#2 行間 URL carry）。
  final String? url;

  const AnsiSegment(this.text, this.style, {this.url});
}

/// パースされた行データ
class ParsedLine {
  /// この行のセグメントリスト
  final List<AnsiSegment> segments;

  /// この行の終了時のスタイル（次の行に引き継ぐ）
  final AnsiStyle endStyle;

  /// この行の終了時の OSC 8 リンク状態（次の行に引き継ぐ・🤝#2 行間 carry）。
  /// null は次の行がリンク外から始まることを意味する。
  final String? endUrl;

  const ParsedLine({
    required this.segments,
    required this.endStyle,
    this.endUrl,
  });

  /// 空行かどうか
  bool get isEmpty => segments.isEmpty || segments.every((s) => s.text.isEmpty);
}
