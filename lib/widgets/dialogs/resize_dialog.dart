import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/backend/domain/multiplexer_pane.dart';
import '../../services/terminal/font_calculator.dart';
import '../../services/tmux/tmux_models.dart';
import '../../services/tmux/tmux_to_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../theme/design_colors.dart';

/// リサイズ結果
class ResizeResult {
  final int cols;
  final int rows;
  const ResizeResult({required this.cols, required this.rows});
}

// ====================================================================
// HerdrResizePaneDialog（tmux の ResizePaneDialog と同構造・絶対値）
// ====================================================================

/// herdr ペインの絶対値リサイズダイアログ（tmux の [ResizePaneDialog] と同構造）。
///
/// ユーザーレビューにより tmux と同じ「プレビュー → 警告 → Cols/Rows 数値入力 →
/// 絶対値プリセット → Cancel/Resize」の構成に改修された。方向パッド・相対量
/// プリセット・ステッパー・現在サイズ表示は削除（ユーザー決定）。
///
/// - プレビューは [_simulatePaneResizeAbsolute]（絶対 cols/rows）で概算表示し、
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

  /// 絶対値プリセット（tmux の [_SizePreset] と共通・80x24 等）。
  List<_SizePreset> get _presets {
    final matchCols = FontCalculator.calculateMaxCols(
      screenWidth: widget.screenWidth,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    final matchRows = FontCalculator.calculateMaxRows(
      screenHeight: widget.screenHeight,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    return [
      _SizePreset(context.l10n.resizePresetStandard, 80, 24),
      _SizePreset(context.l10n.resizePresetWide, 120, 40),
      _SizePreset(context.l10n.resizePresetFullHd, 160, 50),
      _SizePreset(
        context.l10n.resizePresetMatchScreen(matchCols, matchRows),
        matchCols,
        matchRows,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        context.l10n.resizePaneTitle,
        style: const TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // プレビュー（絶対 cols/rows で概算シミュレーション・条件8）。
              // 空リストは非表示・サイズ不明 pane はタイル内「サイズ不明」表記。
              if (widget.panes.isEmpty)
                const SizedBox.shrink()
              else
                _buildPaneGridPreview(
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
                _buildWarning(context.l10n.resizeWarningOtherPanes),
              const SizedBox(height: 12),
              _buildSizeInputRow(
                l10n: context.l10n,
                cols: _cols,
                rows: _rows,
                onColsChanged: (v) => setState(() => _cols = v),
                onRowsChanged: (v) => setState(() => _rows = v),
              ),
              const SizedBox(height: 12),
              _buildPresetChips(
                presets: _presets,
                onSelect: (p) => setState(() {
                  _cols = p.cols;
                  _rows = p.rows;
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.resizeCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, ResizeResult(cols: _cols, rows: _rows)),
          style: FilledButton.styleFrom(
            backgroundColor: DesignColors.primary,
          ),
          child: Text(context.l10n.resizeConfirm),
        ),
      ],
    );
  }
}

/// プリセットサイズ定義
class _SizePreset {
  final String label;
  final int cols;
  final int rows;
  const _SizePreset(this.label, this.cols, this.rows);
}

// ====================================================================
// ResizePaneDialog
// ====================================================================

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

  List<_SizePreset> get _presets {
    final matchCols = FontCalculator.calculateMaxCols(
      screenWidth: widget.screenWidth,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    final matchRows = FontCalculator.calculateMaxRows(
      screenHeight: widget.screenHeight,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    return [
      _SizePreset(context.l10n.resizePresetStandard, 80, 24),
      _SizePreset(context.l10n.resizePresetWide, 120, 40),
      _SizePreset(context.l10n.resizePresetFullHd, 160, 50),
      _SizePreset(
        context.l10n.resizePresetMatchScreen(matchCols, matchRows),
        matchCols,
        matchRows,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    debugPrint('[ResizePaneDialog] build() mediaSize=$mediaSize '
        'allPanes=${widget.allPanesInWindow.length} '
        'target=${widget.targetPane.id} '
        'screenW=${widget.screenWidth} screenH=${widget.screenHeight} '
        'fontSize=${widget.fontSize} fontFamily=${widget.fontFamily}');

    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        context.l10n.resizePaneTitle,
        style: const TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPaneGridPreview(
                l10n: context.l10n,
                // domain 変換（TmuxPane → MultiplexerPane）で同一結果を維持。
                allPanes: widget.allPanesInWindow
                    .map((p) => p.toDomain())
                    .toList(),
                highlightPaneId: widget.targetPane.id,
                previewPaneId: widget.targetPane.id,
                previewCols: _cols,
                previewRows: _rows,
              ),
            const SizedBox(height: 12),
            if (widget.allPanesInWindow.length >= 2)
              _buildWarning(context.l10n.resizeWarningOtherPanes),
            const SizedBox(height: 12),
            _buildSizeInputRow(
              l10n: context.l10n,
              cols: _cols,
              rows: _rows,
              onColsChanged: (v) => setState(() => _cols = v),
              onRowsChanged: (v) => setState(() => _rows = v),
            ),
            const SizedBox(height: 12),
            _buildPresetChips(
              presets: _presets,
              onSelect: (p) => setState(() {
                _cols = p.cols;
                _rows = p.rows;
              }),
            ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.resizeCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, ResizeResult(cols: _cols, rows: _rows)),
          style: FilledButton.styleFrom(
            backgroundColor: DesignColors.primary,
          ),
          child: Text(context.l10n.resizeConfirm),
        ),
      ],
    );
  }
}

// ====================================================================
// ResizeWindowDialog
// ====================================================================

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

  List<_SizePreset> get _presets {
    final matchCols = FontCalculator.calculateMaxCols(
      screenWidth: widget.screenWidth,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    final matchRows = FontCalculator.calculateMaxRows(
      screenHeight: widget.screenHeight,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    return [
      _SizePreset(context.l10n.resizePresetStandard, 80, 24),
      _SizePreset(context.l10n.resizePresetWide, 120, 40),
      _SizePreset(context.l10n.resizePresetFullHd, 160, 50),
      _SizePreset(
        context.l10n.resizePresetMatchScreen(matchCols, matchRows),
        matchCols,
        matchRows,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        context.l10n.resizeWindowTitle,
        style: const TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWindowGridPreview(
                window: widget.window,
                panes: widget.panes,
                currentCols: widget.currentCols,
                currentRows: widget.currentRows,
                l10n: context.l10n,
              ),
            const SizedBox(height: 12),
            if (!widget.supportsResizeWindow)
              _buildWarning(context.l10n.resizeWarningTmuxRequired),
            const SizedBox(height: 12),
            _buildSizeInputRow(
              l10n: context.l10n,
              cols: _cols,
              rows: _rows,
              onColsChanged: (v) => setState(() => _cols = v),
              onRowsChanged: (v) => setState(() => _rows = v),
            ),
            const SizedBox(height: 12),
            _buildPresetChips(
              presets: _presets,
              onSelect: (p) => setState(() {
                _cols = p.cols;
                _rows = p.rows;
              }),
            ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.resizeCancel),
        ),
        FilledButton(
          onPressed: widget.supportsResizeWindow
              ? () => Navigator.pop(
                  context, ResizeResult(cols: _cols, rows: _rows))
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: DesignColors.primary,
          ),
          child: Text(context.l10n.resizeConfirm),
        ),
      ],
    );
  }
}

// ====================================================================
// HerdrResizeTerminalDialog
// ====================================================================

/// herdr のターミナル全体 resize ダイアログ（Select Session の Resize 導線用）。
///
/// tmux の [ResizeWindowDialog] と同一の操作フロー（サイズ入力行 + プリセット
/// チップ + Cancel/Resize ボタン）を提供する。herdr はターミナル全体 = SSH PTY
/// サイズを変更するため、ウィンドウグリッドプレビュー（window / panes）は
/// 不要（ユーザー決定: グリッドプレビュー省略）。タイトルは 'Resize Terminal'
/// （ユーザー決定: 文言変更しない）。
///
/// プリセットタップ / サイズ入力で [_cols] / [_rows] を更新し、Resize ボタンで
/// [ResizeResult] を返して閉じる。共通ビルダー（[_buildSizeInputRow] /
/// [_buildPresetChips] / [_SizePreset]）を [ResizeWindowDialog] と共用する。
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

class _HerdrResizeTerminalDialogState
    extends State<HerdrResizeTerminalDialog> {
  late int _cols;
  late int _rows;

  @override
  void initState() {
    super.initState();
    _cols = widget.currentCols;
    _rows = widget.currentRows;
  }

  List<_SizePreset> get _presets {
    final matchCols = FontCalculator.calculateMaxCols(
      screenWidth: widget.screenWidth,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    final matchRows = FontCalculator.calculateMaxRows(
      screenHeight: widget.screenHeight,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
    );
    return [
      _SizePreset(context.l10n.resizePresetStandard, 80, 24),
      _SizePreset(context.l10n.resizePresetWide, 120, 40),
      _SizePreset(context.l10n.resizePresetFullHd, 160, 50),
      _SizePreset(
        context.l10n.resizePresetMatchScreen(matchCols, matchRows),
        matchCols,
        matchRows,
      ),
    ];
  }

  /// サイドバー付きレイアウトプレビュー（tmux の [_buildWindowGridPreview] 準拠）。
  ///
  /// - 全体を**水色の枠**（[DesignColors.primary] width 2）で囲む
  /// - ヘッダーに「**Herdr (PTY)  cols x rows**」を表示（tmux の
  ///   `'${window.name}  ${currentCols}x$currentRows'` の構造を踏襲）
  /// - 本体: 外枠 = 新しい PTY サイズ（cols x rows）の矩形・**サイドバー**（左端の
  ///   グレー縦帯・エリア幅の約 15%）と**タブ行**（上端のグレー横帯・エリア高の
  ///   約 10%）をグレー表示し、境界に**細い水色線**を引く
  /// - ペイン表示領域（残り）の中央に「**Panel**」テキストを表示（サイズ表示は
  ///   ヘッダーに移したため、ペイン領域は Panel のみ）
  ///
  /// 厳密な幅・高さの再現は herdr の表示設定に依存するため行わない
  /// （ユーザー決定: 「それっぽい」見た目でよい）。cols/rows が小さい場合も
  /// 描画が破綻しないよう、サイドバー幅・タブ行高は比率とピクセル最小値の
  /// 大きい方を採用する（最小サイズガード）。
  Widget _buildLayoutPreview() {
    return Container(
      height: 120,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: DesignColors.canvasDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DesignColors.primary, width: 2),
      ),
      child: Column(
        children: [
          // ヘッダー（tmux のウィンドウヘッダーと同型）。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: DesignColors.surfaceDark,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Text(
              'Herdr (PTY)  $_cols x $_rows',
              style: const TextStyle(
                fontSize: 11,
                color: DesignColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 本体プレビュー（サイドバー + タブ行 + Panel）。
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const pad = 4.0;
                final areaW = constraints.maxWidth - pad * 2;
                final areaH = constraints.maxHeight - pad * 2;
                // サイドバー（エリア幅の 15%・最小 24px）とタブ行（エリア高の 10%・最小 12px）。
                final sidebarW = (areaW * 0.15).clamp(24.0, areaW * 0.5);
                final tabRowH = (areaH * 0.1).clamp(12.0, areaH * 0.5);
                // 外枠: 新しい cols x rows の矩形（縦横比を維持して中央配置）。
                final cols = _cols < 1 ? 1 : _cols;
                final rows = _rows < 1 ? 1 : _rows;
                final scale = math.min(areaW / cols, areaH / rows);
                final previewW = cols * scale;
                final previewH = rows * scale;
                final offsetX = (constraints.maxWidth - previewW) / 2;
                final offsetY = (constraints.maxHeight - previewH) / 2;
                return Stack(
                  children: [
                    // 外枠（ペイン表示領域 = PTY 全体・明るい色）。
                    Positioned(
                      left: offsetX,
                      top: offsetY,
                      width: previewW,
                      height: previewH,
                      child: Container(
                        decoration: BoxDecoration(
                          color: DesignColors.primary.withValues(alpha: 0.15),
                          border: Border.all(
                            color: DesignColors.primary.withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // サイドバー: 左端のグレー縦帯 + 右境界に細い水色線。
                    Positioned(
                      left: offsetX,
                      top: offsetY,
                      width: sidebarW,
                      height: previewH,
                      child: Container(
                        decoration: BoxDecoration(
                          color: DesignColors.borderDark.withValues(alpha: 0.7),
                          border: Border(
                            right: BorderSide(
                              color: DesignColors.primary,
                              width: 1,
                            ),
                          ),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    // タブ行: 上端のグレー横帯 + 下境界に細い水色線。
                    Positioned(
                      left: offsetX + sidebarW,
                      top: offsetY,
                      width: previewW - sidebarW,
                      height: tabRowH,
                      child: Container(
                        decoration: BoxDecoration(
                          color: DesignColors.borderDark.withValues(alpha: 0.7),
                          border: Border(
                            bottom: BorderSide(
                              color: DesignColors.primary,
                              width: 1,
                            ),
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    // ペイン表示領域（サイドバー・タブ行を除く残り）中央に「Panel」。
                    Positioned(
                      left: offsetX + sidebarW,
                      top: offsetY + tabRowH,
                      width: previewW - sidebarW,
                      height: previewH - tabRowH,
                      child: Center(
                        child: Text(
                          'Panel',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: DesignColors.primary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        context.l10n.resizeTerminalTitle,
        style: const TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLayoutPreview(),
              const SizedBox(height: 12),
              _buildSizeInputRow(
                l10n: context.l10n,
                cols: _cols,
                rows: _rows,
                onColsChanged: (v) => setState(() => _cols = v),
                onRowsChanged: (v) => setState(() => _rows = v),
              ),
              const SizedBox(height: 12),
              _buildPresetChips(
                presets: _presets,
                onSelect: (p) => setState(() {
                  _cols = p.cols;
                  _rows = p.rows;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.resizeTerminalDescription,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: DesignColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.resizeCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, ResizeResult(cols: _cols, rows: _rows)),
          style: FilledButton.styleFrom(
            backgroundColor: DesignColors.primary,
          ),
          child: Text(context.l10n.resizeConfirm),
        ),
      ],
    );
  }
}

// ====================================================================
// 共通ビルダー（トップレベル関数）
// ====================================================================

/// tmux の resize-pane を簡易シミュレーションする（絶対 cols/rows・旧ロジック移植）。
///
/// サイズを先に決め、位置を全て再計算する。
/// 1. ウィンドウサイズとセパレータを算出
/// 2. 新しいサイズを決める（カラム幅、カラム内高さ配分）
/// 3. 位置を上から・左から再計算
///
/// [MultiplexerPane] ベースに一般化した（[TmuxPane] は呼び出し側で
/// `toDomain()` 変換済み）。アルゴリズムは従来と同一のため、tmux 側
/// [ResizePaneDialog] のプレビュー結果は従来と同一である（互換維持・H-6）。
List<MultiplexerPane> _simulatePaneResizeAbsolute({
  required List<MultiplexerPane> panes,
  required String targetId,
  required int newCols,
  required int newRows,
}) {
  if (panes.isEmpty) return panes;
  final target =
      panes.firstWhere((p) => p.id == targetId, orElse: () => panes.first);
  if (!panes.any((p) => p.id == targetId)) return panes;

  // === Step 1: ウィンドウサイズ・セパレータ算出 ===
  int winW = 0, winH = 0;
  for (final p in panes) {
    winW = math.max(winW, p.left + p.width);
    winH = math.max(winH, p.top + p.height);
  }
  if (winW == 0 || winH == 0) return panes;

  // 同一カラム（targetと同じleft）
  final colPanes = panes.where((p) => p.left == target.left).toList()
    ..sort((a, b) => a.top.compareTo(b.top));

  // 左隣ペイン（カラムの左に隣接し、垂直方向に重なるペイン）
  final leftNeighbors = panes
      .where(
        (p) =>
            p.left != target.left &&
            p.left + p.width < target.left &&
            colPanes.any(
              (cm) => p.top < cm.top + cm.height && p.top + p.height > cm.top,
            ),
      )
      .toList();

  // 水平セパレータ（カラムと左隣の隙間）
  int hSep = 1; // デフォルト
  if (leftNeighbors.isNotEmpty) {
    hSep = target.left - (leftNeighbors.first.left + leftNeighbors.first.width);
    if (hSep < 0) hSep = 1;
  }

  // 垂直セパレータ（カラム内ペイン間の隙間）
  int vSep = 1; // デフォルト
  if (colPanes.length >= 2) {
    vSep = colPanes[1].top - (colPanes[0].top + colPanes[0].height);
    if (vSep < 0) vSep = 1;
  }

  // === Step 2: 新しいサイズを決める ===

  // カラム幅（clamp: 最小1、最大winW - hSep - 左隣最小1）
  final maxColWidth = leftNeighbors.isNotEmpty ? winW - hSep - 1 : winW;
  final colWidth = newCols.clamp(1, maxColWidth);

  // 左隣幅
  final leftWidth = leftNeighbors.isNotEmpty
      ? math.max<int>(1, winW - hSep - colWidth)
      : 0;

  // カラム内高さ配分
  // カラムの総高さ（元のカラムが使っている高さ）
  final colTop = colPanes.first.top;
  final colBottom = colPanes.last.top + colPanes.last.height;
  final colTotalH = colBottom - colTop;
  final totalVSep = vSep * (colPanes.length - 1);
  final availableH = colTotalH - totalVSep;

  // ターゲットの新しい高さ（clamp: 最小1、最大=使用可能-他ペイン最小各1）
  final otherCount = colPanes.length - 1;
  final maxTargetH = availableH - otherCount; // 他ペインが各最小1
  final targetH = newRows.clamp(1, math.max<int>(1, maxTargetH));

  // 残りの高さを他ペインに元の比率で配分
  final int remainingH = math.max<int>(0, availableH - targetH);
  final otherOriginalSum = colPanes
      .where((p) => p.id != targetId)
      .fold<int>(0, (s, p) => s + p.height);

  final newHeights = <String, int>{};
  newHeights[targetId] = targetH;

  if (otherCount > 0 && otherOriginalSum > 0) {
    int distributed = 0;
    final others = colPanes.where((p) => p.id != targetId).toList();
    for (int i = 0; i < others.length; i++) {
      final p = others[i];
      if (i == others.length - 1) {
        // 最後のペインに残りを全て割り当て（端数調整）
        newHeights[p.id] = math.max<int>(1, remainingH - distributed);
      } else {
        final h = math.max(1, (remainingH * p.height / otherOriginalSum).round());
        newHeights[p.id] = h;
        distributed += h;
      }
    }
  }

  // === Step 3: 位置を再計算 ===

  // 左隣の新しいleft（元のまま）
  final newColLeft = leftNeighbors.isNotEmpty
      ? leftNeighbors.first.left + leftWidth + hSep
      : target.left; // 左隣がなければ元の位置

  // 左隣がなく、右隣がある場合
  // （カラムが左端にある場合は位置は0のまま）

  // カラム内のtopを上から再計算
  final newTops = <String, int>{};
  var currentTop = colTop;
  for (final p in colPanes) {
    newTops[p.id] = currentTop;
    currentTop += (newHeights[p.id] ?? p.height) + vSep;
  }

  // === Step 4: 結果組み立て ===
  return panes.map((p) {
    if (colPanes.any((cp) => cp.id == p.id)) {
      // カラム内ペイン
      return p.copyWith(
        left: newColLeft,
        top: newTops[p.id] ?? p.top,
        width: colWidth,
        height: newHeights[p.id] ?? p.height,
      );
    } else if (leftNeighbors.any((ln) => ln.id == p.id)) {
      // 左隣ペイン（幅変更、位置は元のまま）
      return p.copyWith(width: leftWidth);
    } else {
      // その他（変化なし）
      return p;
    }
  }).toList();
}

/// ペインレイアウトのグリッドプレビュー
///
/// [previewPaneId] が指定された場合、そのペインを [previewCols]x[previewRows] で
/// リサイズしたシミュレーション結果を描画する（絶対 cols/rows・
/// [_simulatePaneResizeAbsolute]）。tmux / herdr の両方で共用する。
///
/// 描画は 0 起点正規化（全 pane の min を引く・herdr の非 0 起点 rect 対応）。
/// [showEstimatedLabel] が true のときは右上に「概算(estimated)」を表示する
/// （条件8）。サイズ不明（width/height <= 0）の pane は「サイズ不明」表記
/// （E1・PaneChooserDialog と同表記）。
Widget _buildPaneGridPreview({
  required List<MultiplexerPane> allPanes,
  required String highlightPaneId,
  String? previewPaneId,
  int? previewCols,
  int? previewRows,
  bool showEstimatedLabel = false,
  required AppLocalizations l10n,
}) {
  if (allPanes.isEmpty) return const SizedBox.shrink();

  // リサイズシミュレーション（絶対 cols/rows・tmux と同一経路）。
  final List<MultiplexerPane> panes;
  if (previewPaneId != null && previewCols != null && previewRows != null) {
    panes = _simulatePaneResizeAbsolute(
      panes: allPanes,
      targetId: previewPaneId,
      newCols: previewCols,
      newRows: previewRows,
    );
  } else {
    panes = allPanes;
  }

  // 0 起点へ正規化（全 pane の min を引く・herdr の非 0 起点 rect 対応）。
  var minLeft = panes.first.left;
  var minTop = panes.first.top;
  int maxRight = 0;
  int maxBottom = 0;
  for (final p in panes) {
    final right = p.left + p.width;
    final bottom = p.top + p.height;
    if (p.left < minLeft) minLeft = p.left;
    if (p.top < minTop) minTop = p.top;
    if (right > maxRight) maxRight = right;
    if (bottom > maxBottom) maxBottom = bottom;
  }
  maxRight -= minLeft;
  maxBottom -= minTop;
  if (maxRight <= 0) maxRight = 1;
  if (maxBottom <= 0) maxBottom = 1;

  return Container(
    height: 120,
    clipBehavior: Clip.hardEdge,
    decoration: BoxDecoration(
      color: DesignColors.canvasDark,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: DesignColors.borderDark),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const pad = 4.0;
        final areaW = constraints.maxWidth - pad * 2;
        final areaH = constraints.maxHeight - pad * 2;

        final scaleX = areaW / maxRight;
        final scaleY = areaH / maxBottom;

        return Padding(
          padding: const EdgeInsets.all(pad),
          child: Stack(
            children: [
              SizedBox(width: areaW, height: areaH),
              // 概算(estimated)ラベル（条件8・右上に小さく表示）。
              if (showEstimatedLabel)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Text(
                    l10n.resizeEstimated,
                    style: const TextStyle(
                      fontSize: 10,
                      color: DesignColors.textMuted,
                    ),
                  ),
                ),
              ...panes.map((pane) {
                final isTarget = pane.id == highlightPaneId;
                final left = (pane.left - minLeft) * scaleX;
                final top = (pane.top - minTop) * scaleY;
                final width = (pane.width * scaleX).clamp(20.0, areaW - left);
                final height = (pane.height * scaleY).clamp(14.0, areaH - top);
                final sizeLabel = (pane.width <= 0 || pane.height <= 0)
                    ? l10n.resizeSizeUnknown
                    : '${pane.width}x${pane.height}';

                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isTarget
                          ? DesignColors.primary.withValues(alpha: 0.25)
                          : DesignColors.surfaceDark,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isTarget
                            ? DesignColors.primary
                            : DesignColors.borderDark,
                        width: isTarget ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          '${pane.index}\n$sizeLabel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: isTarget
                                ? DesignColors.primary
                                : DesignColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    ),
  );
}

/// ウィンドウ全体のグリッドプレビュー（ウィンドウリサイズ用）
Widget _buildWindowGridPreview({
  required TmuxWindow window,
  required List<TmuxPane> panes,
  required int currentCols,
  required int currentRows,
  required AppLocalizations l10n,
}) {
  return Container(
    height: 120,
    clipBehavior: Clip.hardEdge,
    decoration: BoxDecoration(
      color: DesignColors.canvasDark,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: DesignColors.primary, width: 2),
    ),
    child: Column(
      children: [
        // ウィンドウヘッダー
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            color: DesignColors.surfaceDark,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
          ),
          child: Text(
            '${window.name}  ${currentCols}x$currentRows',
            style: const TextStyle(
              fontSize: 11,
              color: DesignColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // ペインレイアウト
        Expanded(
          child: _buildPaneGridPreview(
            l10n: l10n,
            // domain 変換（TmuxPane → MultiplexerPane）。
            allPanes: panes.map((p) => p.toDomain()).toList(),
            highlightPaneId: '', // ウィンドウリサイズではペインハイライトなし
          ),
        ),
      ],
    ),
  );
}

/// 警告メッセージ
Widget _buildWarning(String message) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: DesignColors.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: DesignColors.warning.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded,
            size: 16, color: DesignColors.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              color: DesignColors.warning,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Cols / Rows 数値入力行
Widget _buildSizeInputRow({
  required AppLocalizations l10n,
  required int cols,
  required int rows,
  required ValueChanged<int> onColsChanged,
  required ValueChanged<int> onRowsChanged,
}) {
  return Row(
    children: [
      Expanded(
        child: _buildNumberInput(
          label: l10n.resizeCols,
          value: cols,
          onChanged: onColsChanged,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildNumberInput(
          label: l10n.resizeRows,
          value: rows,
          onChanged: onRowsChanged,
        ),
      ),
    ],
  );
}

/// 単一の数値入力フィールド（ラベル + ◀ 値 ▶）
Widget _buildNumberInput({
  required String label,
  required int value,
  required ValueChanged<int> onChanged,
  int min = 10,
  int max = 500,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: DesignColors.textSecondary,
        ),
      ),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(
          color: DesignColors.inputDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DesignColors.borderDark),
        ),
        child: Row(
          children: [
            _stepButton(
              icon: Icons.chevron_left,
              onPressed: value > min
                  ? () => onChanged((value - 1).clamp(min, max))
                  : null,
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DesignColors.textPrimary,
                ),
              ),
            ),
            _stepButton(
              icon: Icons.chevron_right,
              onPressed: value < max
                  ? () => onChanged((value + 1).clamp(min, max))
                  : null,
            ),
          ],
        ),
      ),
    ],
  );
}

/// ステップボタン（◀ / ▶）
Widget _stepButton({
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  return IconButton(
    icon: Icon(icon, size: 20),
    onPressed: onPressed,
    color: DesignColors.textSecondary,
    disabledColor: DesignColors.textMuted,
    splashRadius: 18,
    padding: const EdgeInsets.all(4),
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
  );
}

/// プリセットChipボタン群
Widget _buildPresetChips({
  required List<_SizePreset> presets,
  required ValueChanged<_SizePreset> onSelect,
}) {
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: presets.map((preset) {
      return ActionChip(
        label: Text(
          preset.label,
          style: const TextStyle(fontSize: 11, color: DesignColors.textPrimary),
        ),
        backgroundColor: DesignColors.keyBackground,
        side: const BorderSide(color: DesignColors.borderDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => onSelect(preset),
      );
    }).toList(),
  );
}
