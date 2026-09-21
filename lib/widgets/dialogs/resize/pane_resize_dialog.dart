import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/tmux/tmux_models.dart';
import '../../../services/tmux/tmux_to_domain.dart';
import 'resize_previews.dart';
import 'resize_result.dart';
import 'resize_shared.dart';

/// ペインリサイズ用ダイアログ
class ResizePaneDialog extends StatefulWidget {
  final TmuxPane targetPane;
  final List<TmuxPane> allPanesInWindow;
  final int currentCols;
  final int currentRows;
  final double screenWidth;
  final double screenHeight;
  final double fontSize;
  final String fontFamily;

  const ResizePaneDialog({
    super.key,
    required this.targetPane,
    required this.allPanesInWindow,
    required this.currentCols,
    required this.currentRows,
    required this.screenWidth,
    required this.screenHeight,
    required this.fontSize,
    required this.fontFamily,
  });

  @override
  State<ResizePaneDialog> createState() => _ResizePaneDialogState();
}

class _ResizePaneDialogState extends State<ResizePaneDialog> {
  late int _cols;
  late int _rows;

  @override
  void initState() {
    super.initState();
    _cols = widget.currentCols;
    _rows = widget.currentRows;
  }

  List<SizePreset> get _presets => SizePreset.standardSet(
    l10n: context.l10n,
    screenWidth: widget.screenWidth,
    screenHeight: widget.screenHeight,
    fontSize: widget.fontSize,
    fontFamily: widget.fontFamily,
  );

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    debugPrint(
      '[ResizePaneDialog] build() mediaSize=$mediaSize '
      'allPanes=${widget.allPanesInWindow.length} '
      'target=${widget.targetPane.id} '
      'screenW=${widget.screenWidth} screenH=${widget.screenHeight} '
      'fontSize=${widget.fontSize} fontFamily=${widget.fontFamily}',
    );

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
        PaneGridPreview(
          l10n: context.l10n,
          // domain 変換（TmuxPane → MultiplexerPane）で同一結果を維持。
          allPanes: widget.allPanesInWindow.map((p) => p.toDomain()).toList(),
          highlightPaneId: widget.targetPane.id,
          previewPaneId: widget.targetPane.id,
          previewCols: _cols,
          previewRows: _rows,
        ),
        const SizedBox(height: 12),
        if (widget.allPanesInWindow.length >= 2)
          WarningBox(message: context.l10n.resizeWarningOtherPanes),
        const SizedBox(height: 12),
      ],
    );
  }
}
