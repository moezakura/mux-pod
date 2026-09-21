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
