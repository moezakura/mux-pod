import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../theme/design_colors.dart';
import 'resize_previews.dart';
import 'resize_result.dart';
import 'resize_shared.dart';

/// herdr のターミナル全体 resize ダイアログ（Select Session の Resize 導線用）。
///
/// tmux の [ResizeWindowDialog] と同一の操作フロー（サイズ入力行 + プリセット
/// チップ + Cancel/Resize ボタン）を提供する。herdr はターミナル全体 = SSH PTY
/// サイズを変更するため、ウィンドウグリッドプレビュー（window / panes）は
/// 不要（ユーザー決定: グリッドプレビュー省略）。タイトルは 'Resize Terminal'
/// （ユーザー決定: 文言変更しない）。
///
/// プリセットタップ / サイズ入力で [_cols] / [_rows] を更新し、Resize ボタンで
/// [ResizeResult] を返して閉じる。共通ビルダー（[SizeInputRow] /
/// [PresetChips] / [SizePreset]）を [ResizeWindowDialog] と共用する。
class HerdrResizeTerminalDialog extends StatefulWidget {
  /// 現在のターミナルサイズ（cols・文字セル単位）。初期値に使う。
  final int currentCols;

  /// 現在のターミナルサイズ（rows・文字セル単位）。初期値に使う。
  final int currentRows;

  /// 画面の論理幅（Match Screen プリセットの算出用）。
  final double screenWidth;

  /// 画面の論理高さ（Match Screen プリセットの算出用）。
  final double screenHeight;

  /// 現在のフォントサイズ（Match Screen プリセットの算出用）。
  final double fontSize;

  /// 現在のフォントファミリー（Match Screen プリセットの算出用）。
  final String fontFamily;

  const HerdrResizeTerminalDialog({
    super.key,
    required this.currentCols,
    required this.currentRows,
    required this.screenWidth,
    required this.screenHeight,
    required this.fontSize,
    required this.fontFamily,
  });

  @override
  State<HerdrResizeTerminalDialog> createState() =>
      _HerdrResizeTerminalDialogState();
}

class _HerdrResizeTerminalDialogState extends State<HerdrResizeTerminalDialog> {
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
      title: context.l10n.resizeTerminalTitle,
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
        HerdrLayoutPreview(cols: _cols, rows: _rows, l10n: context.l10n),
        const SizedBox(height: 12),
      ],
      footer: Text(
        context.l10n.resizeTerminalDescription,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: DesignColors.textMuted),
      ),
    );
  }
}
