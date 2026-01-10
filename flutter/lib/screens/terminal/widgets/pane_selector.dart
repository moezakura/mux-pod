import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/tmux.dart';
import '../../../providers/tmux_provider.dart';
import '../../../services/tmux/tmux_navigation.dart';

/// ペインセレクター
///
/// 現在のウィンドウ内のペインを視覚的に選択できるウィジェット。
class PaneSelector extends ConsumerWidget {
  const PaneSelector({
    super.key,
    required this.connectionId,
    required this.sessionName,
    required this.windowIndex,
    this.onPaneSelected,
  });

  final String connectionId;
  final String sessionName;
  final int windowIndex;
  final void Function(int paneIndex)? onPaneSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(tmuxSessionsProvider(connectionId));
    final navState = ref.watch(tmuxControllerProvider(connectionId));
    final currentPaneIndex = navState.valueOrNull?.paneIndex ?? 0;

    return sessionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        final session = sessions.where((s) => s.name == sessionName).firstOrNull;
        if (session == null) return const SizedBox.shrink();

        final window = session.windows.where((w) => w.index == windowIndex).firstOrNull;
        if (window == null || window.panes.isEmpty) return const SizedBox.shrink();

        return _buildPaneGrid(context, ref, window.panes, currentPaneIndex);
      },
    );
  }

  Widget _buildPaneGrid(
    BuildContext context,
    WidgetRef ref,
    List<TmuxPane> panes,
    int currentPaneIndex,
  ) {
    if (panes.length == 1) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: panes.map((pane) {
          final isSelected = pane.index == currentPaneIndex;
          return _buildPaneChip(context, pane, isSelected);
        }).toList(),
      ),
    );
  }

  Widget _buildPaneChip(BuildContext context, TmuxPane pane, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      avatar: Icon(
        pane.active ? Icons.square : Icons.square_outlined,
        size: 16,
        color: isSelected ? colorScheme.onPrimary : null,
      ),
      label: Text(
        '${pane.index}: ${pane.currentCommand}',
        style: TextStyle(
          color: isSelected ? colorScheme.onPrimary : null,
          fontSize: 12,
        ),
      ),
      backgroundColor: isSelected ? colorScheme.primary : null,
      side: isSelected ? BorderSide.none : null,
      onPressed: () => onPaneSelected?.call(pane.index),
    );
  }
}

/// ペイン方向ナビゲーター
///
/// 上下左右のペイン移動ボタンを提供する。
class PaneDirectionNavigator extends ConsumerWidget {
  const PaneDirectionNavigator({
    super.key,
    required this.connectionId,
    this.size = 36,
    this.onDirectionPressed,
  });

  final String connectionId;
  final double size;
  final void Function(PaneDirection direction)? onDirectionPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: size * 3,
      height: size * 3,
      child: Stack(
        children: [
          // 上
          Positioned(
            left: size,
            top: 0,
            child: _buildDirectionButton(
              context,
              ref,
              PaneDirection.up,
              Icons.keyboard_arrow_up,
            ),
          ),
          // 左
          Positioned(
            left: 0,
            top: size,
            child: _buildDirectionButton(
              context,
              ref,
              PaneDirection.left,
              Icons.keyboard_arrow_left,
            ),
          ),
          // 中央（現在のペイン表示）
          Positioned(
            left: size,
            top: size,
            child: _buildCenterIndicator(context, ref),
          ),
          // 右
          Positioned(
            left: size * 2,
            top: size,
            child: _buildDirectionButton(
              context,
              ref,
              PaneDirection.right,
              Icons.keyboard_arrow_right,
            ),
          ),
          // 下
          Positioned(
            left: size,
            top: size * 2,
            child: _buildDirectionButton(
              context,
              ref,
              PaneDirection.down,
              Icons.keyboard_arrow_down,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionButton(
    BuildContext context,
    WidgetRef ref,
    PaneDirection direction,
    IconData icon,
  ) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, size: size * 0.6),
        onPressed: () async {
          final controller = ref.read(tmuxControllerProvider(connectionId).notifier);
          await controller.movePaneDirection(direction);
          onDirectionPressed?.call(direction);
        },
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildCenterIndicator(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(tmuxControllerProvider(connectionId));
    final currentPane = navState.valueOrNull?.paneIndex ?? 0;

    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          '$currentPane',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// ペイン操作メニュー
///
/// ペインの分割、削除、ズームなどの操作を提供する。
class PaneActionsMenu extends ConsumerWidget {
  const PaneActionsMenu({
    super.key,
    required this.connectionId,
    this.onAction,
  });

  final String connectionId;
  final void Function(PaneAction action)? onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<PaneAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Pane Actions',
      onSelected: (action) => _executeAction(ref, action),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: PaneAction.splitHorizontal,
          child: ListTile(
            leading: Icon(Icons.vertical_split),
            title: Text('Split Horizontal'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: PaneAction.splitVertical,
          child: ListTile(
            leading: Icon(Icons.horizontal_split),
            title: Text('Split Vertical'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: PaneAction.zoom,
          child: ListTile(
            leading: Icon(Icons.fullscreen),
            title: Text('Toggle Zoom'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: PaneAction.close,
          child: ListTile(
            leading: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
            title: Text(
              'Close Pane',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _executeAction(WidgetRef ref, PaneAction action) async {
    final controller = ref.read(tmuxControllerProvider(connectionId).notifier);

    switch (action) {
      case PaneAction.splitHorizontal:
        await controller.splitPaneHorizontal();
      case PaneAction.splitVertical:
        await controller.splitPaneVertical();
      case PaneAction.zoom:
        await controller.togglePaneZoom();
      case PaneAction.close:
        // TODO: Implement pane close with confirmation
        break;
    }

    onAction?.call(action);
  }
}

/// ペイン操作アクション
enum PaneAction {
  splitHorizontal,
  splitVertical,
  zoom,
  close,
}

/// ペインミニマップ
///
/// 現在のウィンドウ内のペインレイアウトを視覚的に表示する。
class PaneMinimap extends ConsumerWidget {
  const PaneMinimap({
    super.key,
    required this.connectionId,
    required this.sessionName,
    required this.windowIndex,
    this.width = 120,
    this.height = 80,
    this.onPaneSelected,
  });

  final String connectionId;
  final String sessionName;
  final int windowIndex;
  final double width;
  final double height;
  final void Function(int paneIndex)? onPaneSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(tmuxSessionsProvider(connectionId));
    final navState = ref.watch(tmuxControllerProvider(connectionId));
    final currentPaneIndex = navState.valueOrNull?.paneIndex ?? 0;

    return sessionsAsync.when(
      loading: () => SizedBox(width: width, height: height),
      error: (_, __) => SizedBox(width: width, height: height),
      data: (sessions) {
        final session = sessions.where((s) => s.name == sessionName).firstOrNull;
        if (session == null) return SizedBox(width: width, height: height);

        final window = session.windows.where((w) => w.index == windowIndex).firstOrNull;
        if (window == null || window.panes.isEmpty) {
          return SizedBox(width: width, height: height);
        }

        return _buildMinimap(context, window.panes, currentPaneIndex);
      },
    );
  }

  Widget _buildMinimap(BuildContext context, List<TmuxPane> panes, int currentPaneIndex) {
    // 全ペインのトータルサイズを計算
    final totalWidth = panes.fold<int>(0, (sum, p) => sum > p.width ? sum : p.width);
    final totalHeight = panes.fold<int>(0, (sum, p) => sum > p.height ? sum : p.height);

    if (totalWidth == 0 || totalHeight == 0) {
      return SizedBox(width: width, height: height);
    }

    final scaleX = width / totalWidth;
    final scaleY = height / totalHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: panes.map((pane) {
          final isSelected = pane.index == currentPaneIndex;
          // 簡易的なレイアウト（実際のtmuxレイアウトを完全に再現するには
          // より複雑な計算が必要）
          final paneWidth = pane.width * scale;

          return Positioned(
            left: 0,
            top: pane.index * (height / panes.length),
            child: GestureDetector(
              onTap: () => onPaneSelected?.call(pane.index),
              child: Container(
                width: paneWidth.clamp(20.0, width),
                height: (height / panes.length) - 2,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: isSelected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${pane.index}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : null,
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
