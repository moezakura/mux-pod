import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../services/terminal/ansi_parser.dart';
import '../../../../services/terminal/font_calculator.dart';
import 'ansi_display_model.dart';
import 'ansi_terminal_model.dart';

/// ターミナルの 1 行レンダリング（P3-2）。
///
/// キャレット行のみ [ValueListenableBuilder] で再構築し、キャレットを
/// RichText 内のインライン WidgetSpan として挿入する（合成・Positioned 不使用）。
/// 行背景レイヤー（C-001）は IgnorePointer で包み、タップ・選択を奪わない。
class AnsiLineRow extends StatelessWidget {
  const AnsiLineRow({
    super.key,
    required this.line,
    required this.index,
    required this.content,
    required this.parsedLineCount,
    required this.paneHeight,
    required this.mode,
    required this.showTerminalCursor,
    required this.resolvedCaret,
    required this.caretVisible,
    required this.baseTextStyle,
    required this.fontSize,
    required this.fontFamily,
    required this.terminalWidth,
    required this.lineHeight,
    required this.needsHorizontalScroll,
  });

  /// 描画する行。
  final ParsedLine line;

  /// この行のインデックス（キャレット行判定に使用）。
  final int index;

  /// 表示モデル（parser・キャレットスパン生成）。
  final AnsiDisplayModel content;

  /// パース済み行数（キャレット行の計算に使用）。
  final int parsedLineCount;

  /// ペインの文字高さ。
  final int paneHeight;

  /// 操作モード。
  final TerminalMode mode;

  /// カーソル表示の有無（設定）。
  final bool showTerminalCursor;

  /// 解決済みカーソル位置（draw ゲートを含む）。
  final ({int x, int y, bool draw}) resolvedCaret;

  /// キャレット点滅リスナー。
  final ValueListenable<bool> caretVisible;

  /// 行に依存しない基本スタイル。
  final TextStyle baseTextStyle;

  /// 実効フォントサイズ。
  final double fontSize;

  /// フォントファミリー。
  final String fontFamily;

  /// ターミナル幅（背景レイヤー・水平スクロール用）。
  final double terminalWidth;

  /// 行の高さ。
  final double lineHeight;

  /// 水平スクロールが必要か（固定幅コンテナ適用判定）。
  final bool needsHorizontalScroll;

  @override
  Widget build(BuildContext context) {
    final textSpan = content.parser.lineToTextSpan(
      line,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );

    // 各行のテキストウィジェット
    Widget lineWidget = Text.rich(
      textSpan,
      style: baseTextStyle,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );

    // カーソルの描画処理
    // カーソル位置の行インデックスを計算
    // parsedLinesには履歴+可視領域が含まれる。
    // 末尾のpaneHeight分が可視領域となる。
    final int cursorLineIndex;
    if (parsedLineCount >= paneHeight) {
      cursorLineIndex = parsedLineCount - paneHeight + resolvedCaret.y;
    } else {
      // 行数がpaneHeight未満の場合は、単純にcursorYを使用（初期状態など）
      cursorLineIndex = resolvedCaret.y;
    }

    // カーソル行: キャレットをStack+Positionedで「合成」せず、
    // テキストレイアウト内の正確な位置に直接挿入する（Issue #70 根本対応）。
    // キャレットはゼロ幅インライン要素として文字境界に置かれ、
    // テキストエンジンが決定する描画位置にそのまま乗る。
    // Phase 4: caret（herdr）が非表示・位置不明・範囲外のときは
    // MuxPod 側カーソルを描画しない（draw ゲート）。
    if (index == cursorLineIndex &&
        mode == TerminalMode.normal &&
        showTerminalCursor &&
        resolvedCaret.draw) {
      // 行のプレーンテキストを取得
      final lineText = line.segments.map((s) => s.text).join();

      // 全角文字を考慮してカラム位置を文字オフセットに変換
      final lineDisplayWidth = FontCalculator.getTextDisplayWidth(lineText);
      final charOffset = FontCalculator.columnToCharOffset(
        lineText,
        resolvedCaret.x,
      );

      // キャレットが行テキスト終端より先にある場合（空行や行末以降）の埋めセル数
      final padColumns = resolvedCaret.x > lineDisplayWidth
          ? resolvedCaret.x - lineDisplayWidth
          : 0;

      lineWidget = ValueListenableBuilder<bool>(
        valueListenable: caretVisible,
        builder: (context, visible, _) {
          return Text.rich(
            content.parser.lineToTextSpanWithCaret(
              line,
              fontSize: fontSize,
              fontFamily: fontFamily,
              caretCharOffset: charOffset,
              padColumns: padColumns,
              caret: visible ? AnsiDisplayModel.caretSpan(fontSize) : null,
            ),
            style: baseTextStyle,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          );
        },
      );
    }

    // 行背景レイヤー（C-001）: 背景色付き行は行末まで、空行は行全体を
    // 塗る。テキストは実データのまま、背景を下層レイヤーで描画する。
    // 背景 Container は IgnorePointer で包み、タップ・選択を奪わない。
    final Color? lineBackground = content.parser.effectiveLineBackgroundColor(
      line,
    );
    if (lineBackground != null) {
      lineWidget = Stack(
        children: [
          // 幅 terminalWidth の背景（非 positioned 子として Stack を
          // pane 幅に固定し、テキスト幅より右側も塗る）。
          IgnorePointer(
            child: SizedBox(
              width: terminalWidth,
              height: lineHeight,
              child: ColoredBox(color: lineBackground),
            ),
          ),
          lineWidget,
        ],
      );
    }

    // 固定幅コンテナ（水平スクロール用）
    if (needsHorizontalScroll) {
      lineWidget = SizedBox(width: terminalWidth, child: lineWidget);
    }

    return lineWidget;
  }
}
