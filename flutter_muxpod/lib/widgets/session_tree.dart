import 'package:flutter/material.dart';

/// tmuxセッションツリー表示Widget
class SessionTree extends StatelessWidget {
  final List<SessionNode> sessions;
  final String? selectedPaneId;
  final void Function(String paneId)? onPaneSelected;
  final void Function(String sessionName)? onSessionDoubleTap;

  const SessionTree({
    super.key,
    required this.sessions,
    this.selectedPaneId,
    this.onPaneSelected,
    this.onSessionDoubleTap,
  });

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
        return _buildSessionNode(context, sessions[index]);
      },
    );
  }

  Widget _buildSessionNode(BuildContext context, SessionNode session) {
    return GestureDetector(
      onDoubleTap: () => onSessionDoubleTap?.call(session.name),
      child: ExpansionTile(
        leading: Icon(
          Icons.folder,
          color: session.attached
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        title: Row(
          children: [
            Text(session.name),
            if (session.attached)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'attached',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        initiallyExpanded: session.attached,
        children: session.windows.map((window) {
          return _buildWindowNode(context, session.name, window);
        }).toList(),
      ),
    );
  }

  Widget _buildWindowNode(BuildContext context, String sessionName, WindowNode window) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: ExpansionTile(
        leading: Icon(
          Icons.tab,
          color: window.active
              ? Theme.of(context).colorScheme.secondary
              : null,
        ),
        title: Text('${window.index}: ${window.name}'),
        initiallyExpanded: window.active,
        children: window.panes.map((pane) {
          return _buildPaneNode(context, pane);
        }).toList(),
      ),
    );
  }

  Widget _buildPaneNode(BuildContext context, PaneNode pane) {
    final isSelected = pane.id == selectedPaneId;

    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: ListTile(
        leading: Icon(
          Icons.terminal,
          color: pane.active
              ? Theme.of(context).colorScheme.tertiary
              : null,
        ),
        title: Text('Pane ${pane.index}'),
        subtitle: Text('${pane.width}x${pane.height}'),
        selected: isSelected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        onTap: () => onPaneSelected?.call(pane.id),
      ),
    );
  }
}

/// セッションノード
class SessionNode {
  final String name;
  final bool attached;
  final List<WindowNode> windows;

  SessionNode({
    required this.name,
    required this.attached,
    required this.windows,
  });
}

/// ウィンドウノード
class WindowNode {
  final int index;
  final String name;
  final bool active;
  final List<PaneNode> panes;

  WindowNode({
    required this.index,
    required this.name,
    required this.active,
    required this.panes,
  });
}

/// ペインノード
class PaneNode {
  final int index;
  final String id;
  final bool active;
  final int width;
  final int height;

  PaneNode({
    required this.index,
    required this.id,
    required this.active,
    required this.width,
    required this.height,
  });
}
