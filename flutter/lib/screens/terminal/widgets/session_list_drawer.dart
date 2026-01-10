import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/tmux.dart';
import '../../../providers/tmux_provider.dart';

/// セッション一覧ドロワー
///
/// tmuxセッション/ウィンドウ/ペインをツリー形式で表示し、
/// ナビゲーションを提供する。
class SessionListDrawer extends ConsumerStatefulWidget {
  const SessionListDrawer({
    super.key,
    required this.connectionId,
    this.onSessionSelected,
    this.onWindowSelected,
    this.onPaneSelected,
    this.onCreateSession,
  });

  final String connectionId;
  final void Function(String sessionName)? onSessionSelected;
  final void Function(String sessionName, int windowIndex)? onWindowSelected;
  final void Function(String sessionName, int windowIndex, int paneIndex)? onPaneSelected;
  final VoidCallback? onCreateSession;

  @override
  ConsumerState<SessionListDrawer> createState() => _SessionListDrawerState();
}

class _SessionListDrawerState extends ConsumerState<SessionListDrawer> {
  final Set<String> _expandedSessions = {};
  final Set<String> _expandedWindows = {};

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(tmuxSessionsProvider(widget.connectionId));
    final navState = ref.watch(tmuxControllerProvider(widget.connectionId));

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(
              child: sessionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildErrorView(context, e),
                data: (sessions) => _buildSessionsList(context, sessions, navState.valueOrNull),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.account_tree),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'tmux Sessions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(tmuxSessionsProvider(widget.connectionId));
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateSessionDialog(context),
            tooltip: 'New Session',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load sessions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                ref.invalidate(tmuxSessionsProvider(widget.connectionId));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsList(
    BuildContext context,
    List<TmuxSession> sessions,
    TmuxNavigationState? currentNav,
  ) {
    if (sessions.isEmpty) {
      return _buildEmptyView(context);
    }

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _buildSessionTile(context, session, currentNav);
      },
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.terminal,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No tmux sessions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Create a session to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showCreateSessionDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Create Session'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(
    BuildContext context,
    TmuxSession session,
    TmuxNavigationState? currentNav,
  ) {
    final isExpanded = _expandedSessions.contains(session.name);
    final isSelected = currentNav?.sessionName == session.name;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            session.attached ? Icons.play_circle : Icons.pause_circle_outline,
            color: isSelected ? colorScheme.primary : null,
          ),
          title: Text(
            session.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : null,
              color: isSelected ? colorScheme.primary : null,
            ),
          ),
          subtitle: Text(
            '${session.windowCount} windows${session.attached ? ' (attached)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (session.windows.isNotEmpty)
                IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedSessions.remove(session.name);
                      } else {
                        _expandedSessions.add(session.name);
                      }
                    });
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          onTap: () {
            widget.onSessionSelected?.call(session.name);
            Navigator.pop(context);
          },
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
        ),
        if (isExpanded)
          ...session.windows.map((window) => _buildWindowTile(
                context,
                session.name,
                window,
                currentNav,
              )),
      ],
    );
  }

  Widget _buildWindowTile(
    BuildContext context,
    String sessionName,
    TmuxWindow window,
    TmuxNavigationState? currentNav,
  ) {
    final windowKey = '$sessionName:${window.index}';
    final isExpanded = _expandedWindows.contains(windowKey);
    final isSelected = currentNav?.sessionName == sessionName &&
        currentNav?.windowIndex == window.index;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 40, right: 16),
          leading: Icon(
            window.active ? Icons.window : Icons.window_outlined,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            size: 20,
          ),
          title: Text(
            '${window.index}: ${window.name}',
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : null,
              color: isSelected ? colorScheme.primary : null,
            ),
          ),
          subtitle: Text(
            '${window.paneCount} panes',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: window.panes.isNotEmpty
              ? IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedWindows.remove(windowKey);
                      } else {
                        _expandedWindows.add(windowKey);
                      }
                    });
                  },
                  visualDensity: VisualDensity.compact,
                )
              : null,
          onTap: () {
            widget.onWindowSelected?.call(sessionName, window.index);
            Navigator.pop(context);
          },
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.2),
        ),
        if (isExpanded)
          ...window.panes.map((pane) => _buildPaneTile(
                context,
                sessionName,
                window.index,
                pane,
                currentNav,
              )),
      ],
    );
  }

  Widget _buildPaneTile(
    BuildContext context,
    String sessionName,
    int windowIndex,
    TmuxPane pane,
    TmuxNavigationState? currentNav,
  ) {
    final isSelected = currentNav?.sessionName == sessionName &&
        currentNav?.windowIndex == windowIndex &&
        currentNav?.paneIndex == pane.index;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 72, right: 16),
      leading: Icon(
        pane.active ? Icons.square : Icons.square_outlined,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 16,
      ),
      title: Text(
        'Pane ${pane.index}',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : null,
          color: isSelected ? colorScheme.primary : null,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        '${pane.currentCommand} (${pane.width}x${pane.height})',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
      ),
      onTap: () {
        widget.onPaneSelected?.call(sessionName, windowIndex, pane.index);
        Navigator.pop(context);
      },
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.1),
      dense: true,
    );
  }

  void _showCreateSessionDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New Session'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Session Name',
              hintText: 'my-session',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(dialogContext);

                final tmuxController = ref.read(
                  tmuxControllerProvider(widget.connectionId).notifier,
                );
                await tmuxController.createSession(name);

                widget.onCreateSession?.call();
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}
