import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../services/backend/domain/multiplexer_pane.dart';
import '../../theme/design_colors.dart';

// ====================================================================
// PaneChooserDialog（tmux / herdr 共通の対象 pane 選択モーダル）
// ====================================================================

/// リサイズ対象 pane をグラフィカルに選択する共通ダイアログ。
///
/// [MultiplexerPane] ベースのため tmux / herdr の両バックエンドで共用できる
/// （選択肢A: 二重実装による描画ズレ・振る舞い乖離の排除・R6）。
/// 旧 `_ResizePaneChooserDialog`（TmuxPane 依存）と旧 `_PaneLayoutVisualizer`
/// の 0 起点正規化（min 引き算方式）を一般化した実装。
///
/// - 0 起点正規化: herdr の rect は 0 起点でない（実測 x:26 / y:1）ため、
///   全 pane の minLeft / minTop を引いて描画する。
/// - 初期選択: [initialPaneId] → リスト内 active（`pane.active`）→ `panes.first`
///   （条件10 フォールバックチェーン）。どれも該当しなければ未選択。
/// - ラベル: [labelBuilder] が非 null ならその結果（herdr の cwd 表示等）、
///   null なら `'Pane N'`（index ベース・条件9）。
/// - 'Selected: Pane N (WxH)' 形式（tmux 互換文言・H-6）。
/// - 未選択時・空リスト時は Resize ボタン disabled（tmux L7501 の前例）。
/// - [onResize] は選択済みのときのみ発火する。失敗時 throw せず return・
///   sync・副作用は呼び出し元コールバック起動のみ。
class PaneChooserDialog extends StatefulWidget {
  /// 選択候補の pane 一覧（空可: グリッド非表示・Resize disabled）。
  final List<MultiplexerPane> panes;

  /// 初期選択 pane の id（null 可・不在時はフォールバックチェーンを適用）。
  final String? initialPaneId;

  /// pane の表示ラベルを生成するビルダー（null なら `'Pane N'`）。
  /// 戻り値 null / 空文字は `'Pane N'` へフォールバックする。
  final String? Function(MultiplexerPane pane)? labelBuilder;

  /// 選択済み pane の id で呼ばれるコールバック（Resize ボタン押下時のみ）。
  final void Function(String paneId) onResize;

  const PaneChooserDialog({
    super.key,
    required this.panes,
    this.initialPaneId,
    this.labelBuilder,
    required this.onResize,
  });

  @override
  State<PaneChooserDialog> createState() => _PaneChooserDialogState();
}

class _PaneChooserDialogState extends State<PaneChooserDialog> {
  String? _selectedPaneId;

  @override
  void initState() {
    super.initState();
    _selectedPaneId = _resolveInitialSelection();
  }

  /// 初期選択フォールバックチェーン（条件10）:
  /// [initialPaneId]（リスト内に存在する場合）→ リスト内 active → panes.first。
  String? _resolveInitialSelection() {
    if (widget.panes.isEmpty) return null;

    final initial = widget.initialPaneId;
    if (initial != null) {
      for (final pane in widget.panes) {
        if (pane.id == initial) return pane.id;
      }
    }
    for (final pane in widget.panes) {
      if (pane.active) return pane.id;
    }
    return widget.panes.first.id;
  }

  MultiplexerPane? get _selectedPane {
    final id = _selectedPaneId;
    if (id == null) return null;
    for (final pane in widget.panes) {
      if (pane.id == id) return pane;
    }
    return null;
  }

  /// ラベル生成（条件9）: labelBuilder の結果 or `'Pane N'`（index ベース）。
  String _labelFor(MultiplexerPane pane) {
    final custom = widget.labelBuilder?.call(pane);
    if (custom != null && custom.isNotEmpty) return custom;
    return context.l10n.termPaneLabel(pane.index);
  }

  /// サイズ表記（width/height <= 0 のサイズ不明 pane は「サイズ不明」・E1）。
  String _sizeLabel(MultiplexerPane pane) {
    if (pane.width <= 0 || pane.height <= 0) {
      return context.l10n.paneChooserSizeUnknown;
    }
    return '${pane.width}x${pane.height}';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPane;

    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        context.l10n.paneChooserTitle,
        style: const TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ペインレイアウトのグリッドプレビュー（空リストは非表示）
              _buildSelectablePaneGrid(),
              const SizedBox(height: 12),
              // 選択中のペイン情報
              if (selected != null)
                Text(
                  context.l10n.paneChooserSelected(
                    _labelFor(selected),
                    _sizeLabel(selected),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                )
              else if (widget.panes.isNotEmpty)
                Text(
                  context.l10n.paneChooserTapToSelect,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DesignColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.paneChooserCancel),
        ),
        FilledButton(
          // 未選択・空リスト時は disabled（tmux L7501 の前例）
          onPressed: selected != null
              ? () => widget.onResize(selected.id)
              : null,
          style: FilledButton.styleFrom(backgroundColor: DesignColors.primary),
          child: Text(context.l10n.paneChooserResize),
        ),
      ],
    );
  }

  Widget _buildSelectablePaneGrid() {
    if (widget.panes.isEmpty) return const SizedBox.shrink();

    // 0 起点へ正規化（全 pane の min を引く・L6527-6547 と同方式）。
    // herdr の layout rect は 0 起点でないため（実測 x:26 / y:1）、min を
    // 引いて描画する（tmux は 0 起点のため正規化は恒等）。
    var minLeft = widget.panes.first.left;
    var minTop = widget.panes.first.top;
    var maxRight = 0;
    var maxBottom = 0;
    for (final pane in widget.panes) {
      final right = pane.left + pane.width;
      final bottom = pane.top + pane.height;
      if (pane.left < minLeft) minLeft = pane.left;
      if (pane.top < minTop) minTop = pane.top;
      if (right > maxRight) maxRight = right;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    maxRight -= minLeft;
    maxBottom -= minTop;
    if (maxRight == 0) maxRight = 1;
    if (maxBottom == 0) maxBottom = 1;

    return Container(
      height: 150,
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
                ...widget.panes.map((pane) {
                  final isSelected = pane.id == _selectedPaneId;
                  // 正規化済みの位置とサイズから Rect を計算
                  final left = (pane.left - minLeft) * scaleX;
                  final top = (pane.top - minTop) * scaleY;
                  final width = (pane.width * scaleX).clamp(20.0, areaW - left);
                  final height = (pane.height * scaleY).clamp(
                    14.0,
                    areaH - top,
                  );

                  return Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: GestureDetector(
                      key: ValueKey('terminal-resize-pane-${pane.id}'),
                      onTap: () => setState(() => _selectedPaneId = pane.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? DesignColors.primary.withValues(alpha: 0.25)
                              : DesignColors.surfaceDark,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected
                                ? DesignColors.primary
                                : DesignColors.borderDark,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              '${pane.index}\n${_sizeLabel(pane)}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? DesignColors.primary
                                    : DesignColors.textSecondary,
                              ),
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
}
