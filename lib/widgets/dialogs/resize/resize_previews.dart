import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/backend/domain/multiplexer_pane.dart';
import '../../../services/tmux/tmux_models.dart';
import '../../../services/tmux/tmux_to_domain.dart';
import '../../../theme/design_colors.dart';
import 'pane_resize_simulator.dart';

/// ペインレイアウトのグリッドプレビュー（resize ダイアログ間共有の内部部品）。
///
/// [previewPaneId] が指定された場合、そのペインを [previewCols]x[previewRows] で
/// リサイズしたシミュレーション結果を描画する（絶対 cols/rows・
/// [simulatePaneResizeAbsolute]）。tmux / herdr の両方で共用する。
///
/// 描画は 0 起点正規化（全 pane の min を引く・herdr の非 0 起点 rect 対応）。
/// [showEstimatedLabel] が true のときは右上に「概算(estimated)」を表示する
/// （条件8）。サイズ不明（width/height <= 0）の pane は「サイズ不明」表記
/// （E1・PaneChooserDialog と同表記）。
///
/// パッケージ外からの使用を意図しない内部部品（resize ダイアログ間共有）。
class PaneGridPreview extends StatelessWidget {
  /// プレビュー対象の pane 一覧（空なら非表示）。
  final List<MultiplexerPane> allPanes;

  /// ハイライト表示する pane ID（リサイズ対象）。
  final String highlightPaneId;

  /// リサイズシミュレーション対象の pane ID（null ならシミュレーションなし）。
  final String? previewPaneId;

  /// シミュレーションの新しい文字幅（[previewPaneId] と同時指定時のみ有効）。
  final int? previewCols;

  /// シミュレーションの新しい文字高さ（[previewPaneId] と同時指定時のみ有効）。
  final int? previewRows;

  /// 右上に「概算(estimated)」ラベルを表示するか（herdr のみ true）。
  final bool showEstimatedLabel;

  /// ローカライズ済み文字列。
  final AppLocalizations l10n;

  const PaneGridPreview({
    super.key,
    required this.allPanes,
    required this.highlightPaneId,
    this.previewPaneId,
    this.previewCols,
    this.previewRows,
    this.showEstimatedLabel = false,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    if (allPanes.isEmpty) return const SizedBox.shrink();

    // リサイズシミュレーション（絶対 cols/rows・tmux と同一経路）。
    final List<MultiplexerPane> panes;
    if (previewPaneId != null && previewCols != null && previewRows != null) {
      panes = simulatePaneResizeAbsolute(
        panes: allPanes,
        targetId: previewPaneId!,
        newCols: previewCols!,
        newRows: previewRows!,
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
                  final height = (pane.height * scaleY).clamp(
                    14.0,
                    areaH - top,
                  );
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
}

/// ウィンドウ全体のグリッドプレビュー（ウィンドウリサイズ用・内部部品）。
///
/// ウィンドウ名 + 現在サイズのヘッダーと、[PaneGridPreview]（シミュレーション
/// なし・ハイライトなし）を合成する。
///
/// パッケージ外からの使用を意図しない内部部品（resize ダイアログ間共有）。
class WindowGridPreview extends StatelessWidget {
  /// 表示対象のウィンドウ（ヘッダーの名前・サイズに使用）。
  final TmuxWindow window;

  /// ウィンドウ内の pane 一覧（domain 変換してプレビューに渡す）。
  final List<TmuxPane> panes;

  /// 現在の文字幅（ヘッダー表示用）。
  final int currentCols;

  /// 現在の文字高さ（ヘッダー表示用）。
  final int currentRows;

  /// ローカライズ済み文字列。
  final AppLocalizations l10n;

  const WindowGridPreview({
    super.key,
    required this.window,
    required this.panes,
    required this.currentCols,
    required this.currentRows,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
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
            child: PaneGridPreview(
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
}

/// サイドバー付きレイアウトプレビュー（herdr PTY 用・内部部品）。
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
/// 大きい方を採用する（最小サイズガード）。さらに cols/rows は最小 1 に
/// clamp してから描画する（min-1 clamp）。
///
/// パッケージ外からの使用を意図しない内部部品（resize ダイアログ間共有）。
class HerdrLayoutPreview extends StatelessWidget {
  /// 新しい文字幅（最小 1 へ clamp して描画）。
  final int cols;

  /// 新しい文字高さ（最小 1 へ clamp して描画）。
  final int rows;

  /// ローカライズ済み文字列。
  final AppLocalizations l10n;

  const HerdrLayoutPreview({
    super.key,
    required this.cols,
    required this.rows,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
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
              l10n.resizeHerdrPtyHeader(cols, rows),
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
                final previewCols = cols < 1 ? 1 : cols;
                final previewRows = rows < 1 ? 1 : rows;
                final scale = math.min(
                  areaW / previewCols,
                  areaH / previewRows,
                );
                final previewW = previewCols * scale;
                final previewH = previewRows * scale;
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
                          l10n.resizePanelLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: DesignColors.primary.withValues(alpha: 0.7),
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
}
