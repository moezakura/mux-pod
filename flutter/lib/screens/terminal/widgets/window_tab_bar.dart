import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/tmux.dart';
import '../../../providers/tmux_provider.dart';

/// ウィンドウタブバー
///
/// tmuxウィンドウを水平タブで表示し、切り替えを可能にする。
class WindowTabBar extends ConsumerWidget {
  const WindowTabBar({
    super.key,
    required this.connectionId,
    required this.sessionName,
    this.onWindowSelected,
    this.onWindowCreate,
    this.onWindowClose,
  });

  final String connectionId;
  final String sessionName;
  final void Function(int windowIndex)? onWindowSelected;
  final VoidCallback? onWindowCreate;
  final void Function(int windowIndex)? onWindowClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(tmuxSessionsProvider(connectionId));
    final navState = ref.watch(tmuxControllerProvider(connectionId));
    final currentWindowIndex = navState.valueOrNull?.windowIndex ?? 0;

    return sessionsAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, __) => const SizedBox(height: 48),
      data: (sessions) {
        final session = sessions.where((s) => s.name == sessionName).firstOrNull;
        if (session == null) return const SizedBox(height: 48);

        return _buildTabBar(context, ref, session.windows, currentWindowIndex);
      },
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    WidgetRef ref,
    List<TmuxWindow> windows,
    int currentWindowIndex,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          // タブリスト（スクロール可能）
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: windows.length,
              itemBuilder: (context, index) {
                final window = windows[index];
                final isSelected = window.index == currentWindowIndex;
                return _buildTab(context, window, isSelected);
              },
            ),
          ),
          // 新規ウィンドウボタン
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: () => _createWindow(ref),
            tooltip: 'New Window',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, TmuxWindow window, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => onWindowSelected?.call(window.index),
      onLongPress: () => _showWindowOptions(context, window),
      child: Container(
        constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.surface : null,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ウィンドウインデックス
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${window.index}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // ウィンドウ名
            Flexible(
              child: Text(
                window.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                  color: isSelected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // アクティブインジケーター
            if (window.active) ...[
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _createWindow(WidgetRef ref) async {
    final controller = ref.read(tmuxControllerProvider(connectionId).notifier);
    await controller.createWindow();
    onWindowCreate?.call();
  }

  void _showWindowOptions(BuildContext context, TmuxWindow window) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename Window'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRenameDialog(context, window);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.close,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Close Window',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onWindowClose?.call(window.index);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, TmuxWindow window) {
    final controller = TextEditingController(text: window.name);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename Window'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Window Name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                // TODO: Implement rename
                Navigator.pop(dialogContext);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }
}

/// コンパクトなウィンドウタブ（ツールバー内用）
class WindowTabBarCompact extends ConsumerWidget {
  const WindowTabBarCompact({
    super.key,
    required this.connectionId,
    required this.sessionName,
    this.onWindowSelected,
    this.onPrevious,
    this.onNext,
  });

  final String connectionId;
  final String sessionName;
  final void Function(int windowIndex)? onWindowSelected;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(tmuxSessionsProvider(connectionId));
    final navState = ref.watch(tmuxControllerProvider(connectionId));
    final currentWindowIndex = navState.valueOrNull?.windowIndex ?? 0;

    return sessionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        final session = sessions.where((s) => s.name == sessionName).firstOrNull;
        if (session == null || session.windows.isEmpty) {
          return const SizedBox.shrink();
        }

        final currentWindow = session.windows
            .where((w) => w.index == currentWindowIndex)
            .firstOrNull;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 前へ
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              onPressed: onPrevious,
              visualDensity: VisualDensity.compact,
              tooltip: 'Previous Window',
            ),
            // 現在のウィンドウ
            GestureDetector(
              onTap: () => _showWindowPicker(context, ref, session.windows, currentWindowIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${currentWindowIndex + 1}/${session.windows.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    if (currentWindow != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        currentWindow.name,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 次へ
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              onPressed: onNext,
              visualDensity: VisualDensity.compact,
              tooltip: 'Next Window',
            ),
          ],
        );
      },
    );
  }

  void _showWindowPicker(
    BuildContext context,
    WidgetRef ref,
    List<TmuxWindow> windows,
    int currentIndex,
  ) {
    showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Window',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              ...windows.map((window) {
                final isSelected = window.index == currentIndex;
                return ListTile(
                  leading: Icon(
                    window.active ? Icons.window : Icons.window_outlined,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    '${window.index}: ${window.name}',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext, window.index);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((selectedIndex) {
      if (selectedIndex != null) {
        onWindowSelected?.call(selectedIndex);
      }
    });
  }
}
