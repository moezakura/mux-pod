import 'package:flutter/material.dart';

import '../models/tmux.dart';

/// セッションツリーウィジェット
///
/// tmuxセッション/ウィンドウ/ペインを階層的に表示する。
class SessionTree extends StatelessWidget {
  const SessionTree({
    super.key,
    required this.sessions,
    this.selectedSession,
    this.selectedWindow,
    this.selectedPane,
    this.onSessionTap,
    this.onWindowTap,
    this.onPaneTap,
    this.onSessionLongPress,
  });

  final List<TmuxSession> sessions;
  final String? selectedSession;
  final int? selectedWindow;
  final int? selectedPane;
  final void Function(TmuxSession session)? onSessionTap;
  final void Function(TmuxSession session, TmuxWindow window)? onWindowTap;
  final void Function(TmuxSession session, TmuxWindow window, TmuxPane pane)? onPaneTap;
  final void Function(TmuxSession session)? onSessionLongPress;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text('No tmux sessions'),
      );
    }

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionTile(
          session: session,
          isSelected: session.name == selectedSession,
          selectedWindow: selectedSession == session.name ? selectedWindow : null,
          selectedPane: selectedSession == session.name ? selectedPane : null,
          onTap: () => onSessionTap?.call(session),
          onLongPress: () => onSessionLongPress?.call(session),
          onWindowTap: (window) => onWindowTap?.call(session, window),
          onPaneTap: (window, pane) => onPaneTap?.call(session, window, pane),
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.isSelected,
    this.selectedWindow,
    this.selectedPane,
    this.onTap,
    this.onLongPress,
    this.onWindowTap,
    this.onPaneTap,
  });

  final TmuxSession session;
  final bool isSelected;
  final int? selectedWindow;
  final int? selectedPane;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TmuxWindow window)? onWindowTap;
  final void Function(TmuxWindow window, TmuxPane pane)? onPaneTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      key: ValueKey('session-${session.name}'),
      leading: Icon(
        session.attached ? Icons.link : Icons.link_off,
        color: session.attached
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        session.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        '${session.windowCount} window${session.windowCount != 1 ? 's' : ''}',
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      initiallyExpanded: isSelected,
      children: session.windows.map((window) {
        return _WindowTile(
          window: window,
          isSelected: selectedWindow == window.index,
          selectedPane: selectedWindow == window.index ? selectedPane : null,
          onTap: () => onWindowTap?.call(window),
          onPaneTap: (pane) => onPaneTap?.call(window, pane),
        );
      }).toList(),
    );
  }
}

class _WindowTile extends StatelessWidget {
  const _WindowTile({
    required this.window,
    required this.isSelected,
    this.selectedPane,
    this.onTap,
    this.onPaneTap,
  });

  final TmuxWindow window;
  final bool isSelected;
  final int? selectedPane;
  final VoidCallback? onTap;
  final void Function(TmuxPane pane)? onPaneTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (window.panes.length <= 1) {
      // 単一ペインの場合はウィンドウのみ表示
      return ListTile(
        leading: const SizedBox(width: 24),
        title: Row(
          children: [
            Icon(
              window.active ? Icons.terminal : Icons.terminal_outlined,
              size: 20,
              color: window.active
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              '${window.index}: ${window.name}',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : null,
              ),
            ),
          ],
        ),
        onTap: onTap,
        selected: isSelected,
        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      );
    }

    // 複数ペインの場合は展開可能
    return ExpansionTile(
      key: ValueKey('window-${window.index}'),
      leading: const SizedBox(width: 24),
      title: Row(
        children: [
          Icon(
            window.active ? Icons.terminal : Icons.terminal_outlined,
            size: 20,
            color: window.active
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '${window.index}: ${window.name}',
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colorScheme.primary : null,
            ),
          ),
        ],
      ),
      initiallyExpanded: isSelected,
      children: window.panes.map((pane) {
        return _PaneTile(
          pane: pane,
          isSelected: selectedPane == pane.index,
          onTap: () => onPaneTap?.call(pane),
        );
      }).toList(),
    );
  }
}

class _PaneTile extends StatelessWidget {
  const _PaneTile({
    required this.pane,
    required this.isSelected,
    this.onTap,
  });

  final TmuxPane pane;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 72),
      leading: Icon(
        pane.active ? Icons.view_agenda : Icons.view_agenda_outlined,
        size: 16,
        color: pane.active
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        'Pane ${pane.index}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        '${pane.currentCommand} (${pane.width}x${pane.height})',
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      dense: true,
      onTap: onTap,
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
    );
  }
}
