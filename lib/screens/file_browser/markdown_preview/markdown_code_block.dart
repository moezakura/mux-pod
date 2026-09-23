import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../theme/app_theme.dart';
import '../../../theme/design_colors.dart';
import '../../../theme/markdown_highlighter.dart';

/// Markdown の `code` 要素に対するカスタムビルダ（C-2）。
///
/// `md.Element.attributes['class']`（`language-xxx`）から言語を抽出し、
/// **言語指定のあるフェンスドコードブロックのみ**ハイライト表示する。
/// class 属性が無い要素（インラインコード・言語なしフェンスドブロック）は
/// null を返して既定描画へフォールバックする（D-2・markdown 7.3.1 は言語
/// 指定時のみ class を付与する・実測確認済み）。
class MarkdownCodeElementBuilder extends MarkdownElementBuilder {
  MarkdownCodeElementBuilder({required this.isDark});

  final bool isDark;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final language = MarkdownHighlighter.languageFromClassAttribute(
      element.attributes['class'],
    );
    if (language == null) return null; // 既定描画へフォールバック
    return MarkdownCodeBlock(
      code: element.textContent,
      language: language,
      isDark: isDark,
    );
  }
}

/// フェンスドコードブロックのハイライト表示（言語指定時）。
///
/// [MarkdownHighlighter] で TextSpan を生成し、横スクロール付きで表示する。
/// 長さ上限（kMaxHighlightChars）超過はハイライトせずプレーン表示（M-3）。
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.code,
    required this.language,
    required this.isDark,
  });

  final String code;
  final String language;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTheme.monoTextStyle.copyWith(
      fontSize: 13,
      color: isDark ? DesignColors.textPrimary : DesignColors.textPrimaryLight,
    );
    final span = MarkdownHighlighter(
      isDark: isDark,
    ).highlight(code, language, baseStyle: baseStyle);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(span),
      ),
    );
  }
}
