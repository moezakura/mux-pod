import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/all.dart';

import 'design_colors.dart';

/// Markdown コードブロックのシンタックスハイライトを担うテーマ部品。
///
/// highlight 0.7.0 を同期実行で使い、コードを [TextSpan] の木へ変換する。
///
/// ## 言語取得（計画 §L3 C-2・syntaxHighlighter は不使用）
/// flutter_markdown_plus の `SyntaxHighlighter.format(String)` は言語を
/// 渡せないため使わず、`MarkdownBody(builders: {'code': …})` の
/// `md.Element.attributes['class']`（`language-xxx`）から
/// [languageFromClassAttribute] で抽出して言語付きハイライトする。
///
/// ## 長さ上限（計画 §L3 M-3）
/// highlight は build 中に同期実行されるため、対象コードが
/// [kMaxHighlightChars] を超える場合はハイライトせずプレーン表示に
/// 割り切る（UI ジャンク / ANR 回避）。
///
/// ## 色（Pattern Map）
/// 色は DesignColors のみを使用する（インライン HEX 禁止）。ライトテーマは
/// 配色を黒方向へ暗色化（[Color.lerp]）してコントラストを確保する。
class MarkdownHighlighter {
  MarkdownHighlighter({required this.isDark});

  /// ハイライト対象コードブロックの長さ上限（文字数）。
  ///
  /// 超過時はプレーン表示（M-3）。目安 20K chars。
  static const int kMaxHighlightChars = 20000;

  /// highlight 0.7.0 のエンジン（プロセス内で 1 回だけ生成し再利用）。
  static final Highlight _highlight = Highlight()..registerLanguages(allLanguages);

  /// ダークテーマかどうか（色マップ切替）。
  final bool isDark;

  /// コードをハイライトして [TextSpan] として返す。
  ///
  /// [language] は highlight の言語名（`language-dart` の `dart` 部分）。
  /// 不明な言語・null は plaintext 扱い（ハイライトなし・既定色）。
  /// [baseStyle] は基底スタイル（モノスペース等）。null なら TextSpan は
  /// スタイルなし（親の DefaultTextStyle に従う）。
  TextSpan highlight(String code, String? language, {TextStyle? baseStyle}) {
    // 長さ上限: 超過はプレーン表示に割り切る（M-3・同期実行のジャンク回避）
    if (code.length > kMaxHighlightChars) {
      return TextSpan(style: baseStyle, text: code);
    }
    final result = _highlight.parse(code, language: language ?? 'plaintext');
    final spans = <InlineSpan>[];
    _visitNodes(result.nodes ?? const [], spans);
    if (spans.isEmpty) {
      // パース結果が空（極端な入力等）はプレーンで表示する
      return TextSpan(style: baseStyle, text: code);
    }
    return TextSpan(style: baseStyle, children: spans);
  }

  /// `class` 属性（`language-xxx`）から言語名を抽出する。
  ///
  /// markdown 7.3.1 の `FencedCodeBlockSyntax` がフェンスドコードブロックの
  /// `code` 要素に `class = 'language-$lang'` を設定する（言語指定時のみ）。
  /// プレフィクス不一致・空は null（インラインコード・言語なしブロック）。
  static String? languageFromClassAttribute(String? className) {
    if (className == null) return null;
    const prefix = 'language-';
    if (!className.startsWith(prefix)) return null;
    final name = className.substring(prefix.length).trim();
    return name.isEmpty ? null : name;
  }

  /// highlight のノード木を [InlineSpan] のリストへ変換する。
  ///
  /// highlight のノードは className を持つラッパー（children）と値を持つ
  /// リーフが分離している。リーフ自体は className を持たないため、親の
  /// 配色を [inheritedStyle] として引き継いで色を付ける（実測確認済み）。
  void _visitNodes(
    List<Node> nodes,
    List<InlineSpan> out, [
    TextStyle? inheritedStyle,
  ]) {
    for (final node in nodes) {
      final style = _spanStyle(node.className) ?? inheritedStyle;
      final hasChildren = (node.children?.isNotEmpty ?? false);
      if (hasChildren) {
        final children = <InlineSpan>[];
        _visitNodes(node.children!, children, style);
        out.add(TextSpan(children: children, style: style));
      } else if (node.value != null && node.value!.isNotEmpty) {
        out.add(TextSpan(text: node.value, style: style));
      }
    }
  }

  /// クラス名に対応する [TextStyle]（未登録クラス・null は既定色のみ）。
  TextStyle? _spanStyle(String? className) {
    if (className == null) return null;
    final color = _colorFor(className);
    if (color == null) return null;
    final style = TextStyle(color: color);
    if (className == 'comment' || className == 'emphasis') {
      return style.copyWith(fontStyle: FontStyle.italic);
    }
    if (className == 'strong') {
      return style.copyWith(fontWeight: FontWeight.bold);
    }
    return style;
  }

  /// クラス名 → 色（isDark で切替）。未登録は既定色（null）。
  Color? _colorFor(String className) {
    final map = isDark ? _darkColors : _lightColors;
    return map[className];
  }

  /// ダークテーマの配色（DesignColors ベース）。
  static const Map<String, Color> _darkColors = {
    'comment': DesignColors.textMuted,
    'keyword': DesignColors.terminalMagenta,
    'selector-tag': DesignColors.terminalMagenta,
    'doctag': DesignColors.terminalMagenta,
    'string': DesignColors.terminalGreen,
    'regexp': DesignColors.terminalGreen,
    'meta': DesignColors.terminalGreen,
    'symbol': DesignColors.terminalGreen,
    'bullet': DesignColors.terminalGreen,
    'template-tag': DesignColors.terminalGreen,
    'template-variable': DesignColors.terminalGreen,
    'number': DesignColors.terminalYellow,
    'literal': DesignColors.terminalYellow,
    'title': DesignColors.terminalBlue,
    'function': DesignColors.terminalBlue,
    'section': DesignColors.terminalBlue,
    'name': DesignColors.terminalBlue,
    'type': DesignColors.terminalCyan,
    'built_in': DesignColors.terminalCyan,
    'params': DesignColors.terminalCyan,
    'attr': DesignColors.warning,
    'attribute': DesignColors.warning,
    'variable': DesignColors.warning,
    'property': DesignColors.warning,
    'addition': DesignColors.success,
    'deletion': DesignColors.error,
  };

  /// ライトテーマの配色（ダーク配色を暗色化してコントラスト確保）。
  static final Map<String, Color> _lightColors = {
    for (final entry in _darkColors.entries)
      entry.key: Color.lerp(entry.value, Colors.black, 0.25)!,
  };
}