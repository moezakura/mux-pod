import 'package:flutter/material.dart';

import '../../theme/design_colors.dart';
import '../../l10n/l10n_ext.dart';
import '../../widgets/multiplexer_tiles.dart';
import 'herdr/herdr_types.dart';
import 'pane_layout_visualizer.dart' show PaneLayoutVisualizer;
import 'selector_launch.dart' show showMultiplexerSheet;
import 'selector_sheet.dart' show SelectorContent;

/// herdr セレクタ表示のアダプタ（ui/root 領域・HerdrSheetHost 実装）。
///
/// herdr 側（HerdrSelectorPresenter 等）は [HerdrSheetContent]（汎用タイル +
/// 分割プレビュー）を組み立て、本クラスが ui の共通シート基盤
/// （`showMultiplexerSheet`）へ変換して描画する。依存方向は
/// ui → herdr_types（一方向・循環なし）。
class HerdrSheetHostImpl implements HerdrSheetHost {
  HerdrSheetHostImpl(this.contextOf);

  /// シートを開く BuildContext の供給元（root State）。
  final BuildContext Function() contextOf;

  @override
  Future<void> show({
    required String title,
    required IconData icon,
    bool topExpected = false,
    required ConcurrentSelectorLoader load,
  }) {
    return showMultiplexerSheet(
      context: contextOf(),
      title: title,
      icon: icon,
      topExpected: topExpected,
      asyncContent: () async {
        final content = await load();
        return SelectorContent(
          headerActions: [
            for (final action in content.headerActions)
              IconButton(
                tooltip: action.tooltip,
                icon: Icon(action.icon),
                onPressed: action.onPressed,
              ),
          ],
          top: content.top == null ? null : _buildTop(content.top!),
          children: [for (final tile in content.tiles) _buildTile(tile)],
        );
      },
    );
  }

  Widget _buildTop(HerdrSheetTopData top) {
    return PaneLayoutVisualizer(
      panes: top.window.panes,
      activePaneId: top.activePaneId,
      onPaneSelected: top.onSelectPane,
      onSplitRequested: top.onSplitPane,
    );
  }

  Widget _buildTile(HerdrSheetTile tile) {
    // HEAD 互換: workspace / tab / pane は専用タイル（テストが型を参照）で
    // 描画する。汎用 ListTile は型未指定時のみ（実質 unused）。
    if (tile.session != null) {
      return MultiplexerSessionTile(
        key: tile.key,
        session: tile.session!,
        isActive: tile.isActive,
        onTap: tile.onTap,
      );
    }
    if (tile.window != null) {
      return MultiplexerWindowTile(
        key: tile.key,
        window: tile.window!,
        isActive: tile.isActive,
        onTap: tile.onTap,
        onRename: tile.onRename,
        onResize: tile.onResize,
        onClose: tile.onClose,
      );
    }
    if (tile.pane != null) {
      return MultiplexerPaneTile(
        key: tile.key,
        pane: tile.pane!,
        paneTitle: tile.title ?? '',
        subtitle: tile.subtitle,
        isActive: tile.isActive,
        onTap: tile.onTap,
        onLongPress: tile.onLongPress,
        onResize: tile.onResize,
        onClose: tile.onClose,
      );
    }
    final primary = Theme.of(contextOf()).colorScheme.primary;
    final colorScheme = Theme.of(contextOf()).colorScheme;
    final l10n = contextOf().l10n;
    final hasActions =
        tile.onRename != null || tile.onResize != null || tile.onClose != null;
    return ListTile(
      key: tile.key,
      leading: tile.isActive ? Icon(Icons.check, color: primary) : null,
      title: tile.title == null
          ? null
          : Text(
              tile.title!,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tile.isActive
                    ? primary
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
      subtitle: tile.subtitle == null ? null : Text(tile.subtitle!),
      trailing: hasActions
          ? PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (menuContext) => [
                if (tile.onRename != null)
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(
                          Icons.drive_file_rename_outline,
                          size: 18,
                          color: colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.muxRenameWindow),
                      ],
                    ),
                  ),
                if (tile.onResize != null)
                  PopupMenuItem(
                    value: 'resize',
                    child: Row(
                      children: [
                        Icon(
                          Icons.aspect_ratio,
                          size: 18,
                          color: colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.muxResizePane),
                      ],
                    ),
                  ),
                if (tile.onClose != null)
                  PopupMenuItem(
                    value: 'close',
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 18, color: DesignColors.error),
                        const SizedBox(width: 8),
                        Text(
                          l10n.muxClosePane,
                          style: TextStyle(color: DesignColors.error),
                        ),
                      ],
                    ),
                  ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    tile.onRename?.call();
                  case 'resize':
                    tile.onResize?.call();
                  case 'close':
                    tile.onClose?.call();
                }
              },
            )
          : null,
      onTap: tile.onTap,
      onLongPress: tile.onLongPress,
    );
  }
}
