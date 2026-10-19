import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import '../../../../services/terminal/ansi_parser.dart';
import '../../../../services/terminal/font_calculator.dart';
import '../../../../utils/external_links.dart';
import 'ansi_display_model.dart';
import 'ansi_link_probe.dart';
import 'ansi_terminal_model.dart';

/// ターミナルの 1 行レンダリング（P3-2）。
///
/// キャレット行のみ [ValueListenableBuilder] で再構築し、キャレットを
/// RichText 内のインライン WidgetSpan として挿入する（合成・Positioned 不使用）。
/// 行背景レイヤー（C-001）は IgnorePointer で包み、タップ・選択を奪わない。
///
/// OSC 8 リンク（Issue #61・Phase 5 #14）: リンク行では recognizer 付き
/// TextSpan を構築する。recognizer のライフサイクル契約:
///
/// - **生成者** = [_AnsiLineRowState]（選択モード以外でリンク行のときのみ。
///   生成時に `tryParseExternalHttpUri` で scheme フィルタし、非 https/http は
///   「装飾付き・タップ不可」（D8 仕様））。
/// - **破棄者** = 同 State（`dispose` + `didUpdateWidget` で行 / モード変化時に
///   全 dispose）。
/// - **キャッシュ相互作用** = なし（resolver 付き span はスパンキャッシュを
///   読みも書きもしない＝レンダラ契約）。点滅中は `identical(line)` 判定で
///   recognizer を使い回すため蓄積しない。
/// - **同一 URL の recognizer 共有契約（M4）**: 行内に同一 URL が複数出現して
///   も URL をキーに 1 インスタンスを共有する。
class AnsiLineRow extends StatefulWidget {
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
    this.onLinkTap,
    this.probeRegistry,
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

  /// OSC 8 リンクタップのコールバック受け口（Issue #61）。
  ///
  /// 起動コーディネータ（terminal_view_shell）への伝搬先。null 既定で、
  /// 未接続のときは recognizer は生成されるがタップしても何も起こらない。
  final void Function(String url)? onLinkTap;

  /// 選択モードのリンクタップ解決レジストリ（Phase 5 #15）。
  ///
  /// 非 null のとき本行の State を登録し、選択モードのタッププローブ
  /// （[AnsiSelectModeTapProbe]）からの global 位置解決に応じる。
  /// null は登録なし（従来挙動）。
  final AnsiLinkProbeRegistry? probeRegistry;

  @override
  State<AnsiLineRow> createState() => _AnsiLineRowState();
}

class _AnsiLineRowState extends State<AnsiLineRow>
    implements AnsiLinkProbeTarget {
  /// URL → タップ認識子（生成者・破棄者とも本 State）。
  final Map<String, TapGestureRecognizer> _recognizers =
      <String, TapGestureRecognizer>{};

  /// recognizer を生成した行（identical 判定による使い回しガード）。
  ParsedLine? _builtForLine;

  @override
  void initState() {
    super.initState();
    widget.probeRegistry?.register(this);
  }

  @override
  void didUpdateWidget(AnsiLineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 行 or モード変化で recognizer を作り直す（旧インスタンスは確実に
    // dispose。次の build で _ensureRecognizers が再生成する）。
    if (!identical(oldWidget.line, widget.line) ||
        oldWidget.mode != widget.mode) {
      _disposeRecognizers();
      _builtForLine = null;
    }
    // プローブ登録先の付け替え。
    if (!identical(oldWidget.probeRegistry, widget.probeRegistry)) {
      oldWidget.probeRegistry?.unregister(this);
      widget.probeRegistry?.register(this);
    }
  }

  @override
  void dispose() {
    widget.probeRegistry?.unregister(this);
    _disposeRecognizers();
    super.dispose();
  }

  /// 保有する recognizer をすべて破棄する（破棄者 = 本 State）。
  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// 行内の distinct URL に対して recognizer を用意する。
  ///
  /// `identical(_builtForLine, widget.line)` の間は再生成しないため、
  /// 500ms 点滅で span が再構築されても recognizer は使い回される
  /// （蓄積しない・critic R1 回答）。
  void _ensureRecognizers() {
    if (identical(_builtForLine, widget.line)) {
      return;
    }
    _disposeRecognizers();
    for (final url
        in widget.line.segments
            .map((segment) => segment.url)
            .whereType<String>()
            .toSet()) {
      // scheme フィルタ: 非 https/http は装飾のみ・タップ不可（D8 仕様）。
      // タップ時のガードは起動コーディネータ側で二重防御となる。
      final uri = tryParseExternalHttpUri(url);
      if (uri == null) {
        continue;
      }
      _recognizers[url] = TapGestureRecognizer()
        ..onTap = () => widget.onLinkTap?.call(url);
    }
    _builtForLine = widget.line;
  }

  /// レンダラへ渡す resolver（URL → 生成済み recognizer。非識別 URL は
  /// recognizer 無しの装飾のみ）。
  LinkTapResolver get _linkTapResolver =>
      (url) => _recognizers[url];

  /// リンク recognizer を生成してよいモードか。
  ///
  /// 選択モードは SelectionArea がタップを吸うため recognizer を生成せず、
  /// タップはプローブ経路（#15）で発火する。通常 / scrollSend は
  /// recognizer 直結（scrollSend は onTap 非配置の既存設計により
  /// 縦ドラッグ送信と arena で両立する）。
  bool get _linkTappable => widget.mode != TerminalMode.select;

  bool get _hasLinks =>
      widget.line.segments.any((segment) => segment.url != null);

  // === AnsiLinkProbeTarget 実装（選択モードタッププローブ・#15） ===

  @override
  bool get isProbeValid => mounted;

  @override
  String? resolveLinkAt(Offset globalPosition) {
    if (!mounted) {
      return null;
    }
    final paragraph = _findRenderParagraph();
    if (paragraph == null) {
      return null;
    }
    final local = paragraph.globalToLocal(globalPosition);
    if (!paragraph.size.contains(local)) {
      return null;
    }
    final position = paragraph.getPositionForOffset(local);
    return _urlAtTextOffset(position.offset);
  }

  /// 本行の RichText（RenderParagraph）を探す。
  ///
  /// 行は Stack / SizedBox 等で包まれ得るため、レンダーツリーを下降して
  /// 最初の RenderParagraph を返す（1 行にはテキスト RichText が 1 つ）。
  RenderParagraph? _findRenderParagraph() {
    final renderObject = context.findRenderObject();
    if (renderObject == null) {
      return null;
    }
    if (renderObject is RenderParagraph) {
      return renderObject;
    }
    RenderParagraph? found;
    void visit(RenderObject child) {
      if (found != null) {
        return;
      }
      if (child is RenderParagraph) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    visit(renderObject);
    return found;
  }

  /// セグメント累積文字数から [offset] を含むセグメントの URL を返す。
  ///
  /// span テキストはセグメントテキストの連結と文字位置 1:1 で対応する
  /// （inverse 時の NBSP 置換は文字数不変）。選択モードではキャレット行の
  /// WidgetSpan 挿入が行われない（キャレット分岐は normal モード限定）ため
  /// この対応が成立する。行末（パディング領域等）は null。
  String? _urlAtTextOffset(int offset) {
    var start = 0;
    for (final segment in widget.line.segments) {
      final end = start + segment.text.length;
      if (offset >= start && offset < end) {
        return segment.url;
      }
      start = end;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // カーソルの描画処理
    // カーソル位置の行インデックスを計算
    // parsedLinesには履歴+可視領域が含まれる。
    // 末尾のpaneHeight分が可視領域となる。
    final int cursorLineIndex;
    if (widget.parsedLineCount >= widget.paneHeight) {
      cursorLineIndex =
          widget.parsedLineCount - widget.paneHeight + widget.resolvedCaret.y;
    } else {
      // 行数がpaneHeight未満の場合は、単純にcursorYを使用（初期状態など）
      cursorLineIndex = widget.resolvedCaret.y;
    }
    final isCaretRow =
        widget.index == cursorLineIndex &&
        widget.mode == TerminalMode.normal &&
        widget.showTerminalCursor &&
        widget.resolvedCaret.draw;

    // リンク行かつタップ可能モードのときのみ recognizer を用意する
    // （identical ガード内で 1 回だけ生成・点滅中は使い回し）。
    final wantsLinkSpan = _hasLinks && _linkTappable;
    if (wantsLinkSpan) {
      _ensureRecognizers();
    }

    // リンク×キャレット行（M3）: 外側構築は resolver なし（キャッシュ経路）
    // に留め、resolver 渡しは blink builder 内の lineToTextSpanWithCaret
    // に限定する（二重構築回避・ツリー形状不変）。
    final LinkTapResolver? outerResolver = wantsLinkSpan && !isCaretRow
        ? _linkTapResolver
        : null;

    final textSpan = widget.content.parser.lineToTextSpan(
      widget.line,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
      linkTapResolver: outerResolver,
    );

    // 各行のテキストウィジェット
    Widget lineWidget = Text.rich(
      textSpan,
      style: widget.baseTextStyle,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );

    // カーソル行: キャレットをStack+Positionedで「合成」せず、
    // テキストレイアウト内の正確な位置に直接挿入する（Issue #70 根本対応）。
    // キャレットはゼロ幅インライン要素として文字境界に置かれ、
    // テキストエンジンが決定する描画位置にそのまま乗る。
    // Phase 4: caret（herdr）が非表示・位置不明・範囲外のときは
    // MuxPod 側カーソルを描画しない（draw ゲート）。
    if (isCaretRow) {
      // 行のプレーンテキストを取得
      final lineText = widget.line.segments.map((s) => s.text).join();

      // 全角文字を考慮してカラム位置を文字オフセットに変換
      final lineDisplayWidth = FontCalculator.getTextDisplayWidth(lineText);
      final charOffset = FontCalculator.columnToCharOffset(
        lineText,
        widget.resolvedCaret.x,
      );

      // キャレットが行テキスト終端より先にある場合（空行や行末以降）の埋めセル数
      final padColumns = widget.resolvedCaret.x > lineDisplayWidth
          ? widget.resolvedCaret.x - lineDisplayWidth
          : 0;

      lineWidget = ValueListenableBuilder<bool>(
        valueListenable: widget.caretVisible,
        builder: (context, visible, _) {
          return Text.rich(
            widget.content.parser.lineToTextSpanWithCaret(
              widget.line,
              fontSize: widget.fontSize,
              fontFamily: widget.fontFamily,
              caretCharOffset: charOffset,
              padColumns: padColumns,
              caret: visible
                  ? AnsiDisplayModel.caretSpan(widget.fontSize)
                  : null,
              // H2: blink off 相（caret == null → lineToTextSpan 委譲）でも
              // resolver が透過される（レンダラ実装）。on/off 両相で発火する。
              linkTapResolver: wantsLinkSpan ? _linkTapResolver : null,
            ),
            style: widget.baseTextStyle,
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
    final Color? lineBackground = widget.content.parser
        .effectiveLineBackgroundColor(widget.line);
    if (lineBackground != null) {
      lineWidget = Stack(
        children: [
          // 幅 terminalWidth の背景（非 positioned 子として Stack を
          // pane 幅に固定し、テキスト幅より右側も塗る）。
          IgnorePointer(
            child: SizedBox(
              width: widget.terminalWidth,
              height: widget.lineHeight,
              child: ColoredBox(color: lineBackground),
            ),
          ),
          lineWidget,
        ],
      );
    }

    // 固定幅コンテナ（水平スクロール用）
    if (widget.needsHorizontalScroll) {
      lineWidget = SizedBox(width: widget.terminalWidth, child: lineWidget);
    }

    return lineWidget;
  }
}
