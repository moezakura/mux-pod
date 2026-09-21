import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/tmux/tmux_models.dart';
import 'resize_previews.dart';
import 'resize_result.dart';
import 'resize_shared.dart';

/// ウィンドウリサイズ用ダイアログ
class ResizeWindowDialog extends StatefulWidget {
  final TmuxWindow window;
  final List<TmuxPane> panes;
  final int currentCols;
  final int currentRows;
  final double screenWidth;
  final double screenHeight;
  final double fontSize;
  final String fontFamily;
  final bool supportsResizeWindow;

  const ResizeWindowDialog({
    super.key,
    required this.window,
    required this.panes,
    required this.currentCols,
    required this.currentRows,
    required this.screenWidth,
    required this.screenHeight,
    required this.fontSize,
    required this.fontFamily,
    required this.supportsResizeWindow,
  });

  @override
  State<ResizeWindowDialog> createState() => _ResizeWindowDialogState();
}

class _ResizeWindowDialogState extends State<ResizeWindowDialog> {
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
    return ResizeDialogScaffold(
      title: context.l10n.resizeWindowTitle,
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
      confirmEnabled: widget.supportsResizeWindow,
      content: [
        WindowGridPreview(
          window: widget.window,
          panes: widget.panes,
          currentCols: widget.currentCols,
          currentRows: widget.currentRows,
          l10n: context.l10n,
        ),
        const SizedBox(height: 12),
        if (!widget.supportsResizeWindow)
          WarningBox(message: context.l10n.resizeWarningTmuxRequired),
        const SizedBox(height: 12),
      ],
    );
  }
}
