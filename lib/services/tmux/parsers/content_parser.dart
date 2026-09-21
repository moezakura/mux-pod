// inventory: TMUX-CONTENT-PARSER-000
/// tmux ペインコンテンツのパースと ANSI 除去
library;

import '../tmux_models.dart';

/// tmux ペインコンテンツのパースと ANSI 除去。
class TmuxContentParser {
  // inventory: TMUX-PARSER-011
  /// capture-pane出力をパース（ANSIエスケープ付き）
  static TmuxPaneContent parse(
    String output, {
    int? width,
    int? height,
    bool stripTrailingEmptyLines = true,
  }) {
    final lines = output.split('\n');

    if (stripTrailingEmptyLines) {
      while (lines.isNotEmpty && lines.last.trim().isEmpty) {
        lines.removeLast();
      }
    }

    return TmuxPaneContent(
      lines: lines,
      width: width ?? _guessWidth(lines),
      height: lines.length,
      hasAnsiColors: output.contains('\x1b['),
    );
  }

  // inventory: TMUX-PARSER-012
  /// capture-pane出力からプレーンテキストを抽出
  static String stripAnsi(String text) {
    // ANSIエスケープシーケンスを削除
    return text.replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), '');
  }

  // inventory: TMUX-PARSER-017
  /// 行から幅を推測
  static int _guessWidth(List<String> lines) {
    if (lines.isEmpty) return 80;
    int maxWidth = 0;
    for (final line in lines) {
      final stripped = stripAnsi(line);
      if (stripped.length > maxWidth) {
        maxWidth = stripped.length;
      }
    }
    return maxWidth > 0 ? maxWidth : 80;
  }
}
