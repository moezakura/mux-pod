import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/backend/domain/multiplexer_pane.dart';
import 'pane_resize_simulator.dart';
import 'resize_previews.dart';
import 'resize_result.dart';
import 'resize_shared.dart';

/// herdr ペインの絶対値リサイズダイアログ（tmux の [ResizePaneDialog] と同構造）。
///
/// ユーザーレビューにより tmux と同じ「プレビュー → 警告 → Cols/Rows 数値入力 →
/// 絶対値プリセット → Cancel/Resize」の構成に改修された。方向パッド・相対量
/// プリセット・ステッパー・現在サイズ表示は削除（ユーザー決定）。
///
/// - プレビューは [simulatePaneResizeAbsolute]（絶対 cols/rows）で概算表示し、
///   「概算(estimated)」ラベルを付ける（条件8）。サイズ不明（width/height
///   <= 0）の pane は「サイズ不明」表記（E1）。
/// - 警告は pane 2 枚以上のときのみ表示（条件4・tmux と同レベル）。
/// - 戻り値は tmux 共通の [ResizeResult]（絶対 cols/rows）。
class HerdrResizePaneDialog extends StatefulWidget {
  /// プレビュー・警告判定用の pane 一覧（空可: プレビュー非表示・警告非表示）。
  final List<MultiplexerPane> panes;

  /// リサイズ対象の pane ID（例: "w1:p1"）。
  final String targetPaneId;

  /// 現在の文字幅（セル数・pane rect の width）。
  final int currentCols;

  /// 現在の文字高さ（セル数・pane rect の height）。
  final int currentRows;

  /// 画面の論理幅（Match Screen プリセットの算出用）。
  final double screenWidth;

  /// 画面の論理高さ（Match Screen プリセットの算出用）。
  final double screenHeight;

  /// 現在のフォントサイズ（Match Screen プリセットの算出用）。
  final double fontSize;

  /// 現在のフォントファミリー（Match Screen プリセットの算出用）。
  final String fontFamily;

  const HerdrResizePaneDialog({
    super.key,
    required this.targetPaneId,
    this.panes = const [],
    this.currentCols = 0,
    this.currentRows = 0,
    this.screenWidth = 0,
    this.screenHeight = 0,
    this.fontSize = 14,
    this.fontFamily = 'monospace',
  });

  @override
  State<HerdrResizePaneDialog> createState() => _HerdrResizePaneDialogState();
}

class _HerdrResizePaneDialogState extends State<HerdrResizePaneDialog> {
  late int _cols;
  late int _rows;

  @override
  void initState() {
    super.initState();
    _cols = widget.currentCols;
    _rows = widget.currentRows;
  }

  /// 絶対値プリセット（tmux と共通・80x24 等）。
  List<SizePreset> get _presets => SizePreset.standardSet(
    l10n: context.l10n,
    screenWidth: widget.screenWidth,
    screenHeight: widget.screenHeight,
    fontSize: widget.fontSize,
    fontFamily: widget.fontFamily,
  );

  @override
  Widget build(BuildContext context) {
    return ResizeDialogScaffold(
      title: context.l10n.resizePaneTitle,
      cols: _cols,
      rows: _rows,
      onColsChanged: (v) => setState(() => _cols = v),
      onRowsChanged: (v) => setState(() => _rows = v),
      presets: _presets,
      onSelectPreset: (p) => setState(() {
        _cols = p.cols;
        _rows = p.rows;
      }),
      onCancel: () => Navigator.pop(context),
      onConfirm: () =>
          Navigator.pop(context, ResizeResult(cols: _cols, rows: _rows)),
      content: [
        // プレビュー（絶対 cols/rows で概算シミュレーション・条件8）。
        // 空リストは非表示・サイズ不明 pane はタイル内「サイズ不明」表記。
        if (widget.panes.isEmpty)
          const SizedBox.shrink()
        else
          PaneGridPreview(
            l10n: context.l10n,
            allPanes: widget.panes,
            highlightPaneId: widget.targetPaneId,
            previewPaneId: widget.targetPaneId,
            previewCols: _cols,
            previewRows: _rows,
            showEstimatedLabel: true,
          ),
        const SizedBox(height: 12),
        // 警告: pane 2 枚以上のときのみ（条件4・tmux と同レベル）。
        if (widget.panes.length >= 2)
          WarningBox(message: context.l10n.resizeWarningOtherPanes),
        const SizedBox(height: 12),
      ],
    );
  }
}
