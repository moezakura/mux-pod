import 'package:flutter/material.dart';

/// セッション/ウィンドウ/ペインを表示するドロワー
class SessionDrawer extends StatelessWidget {
  final List<SessionItem> sessions;
  final String? activeSessionName;
  final int? activeWindowIndex;
  final String? activePaneId;
  final void Function(String sessionName)? onSessionTap;
  final void Function(String sessionName, int windowIndex)? onWindowTap;
  final void Function(String paneId)? onPaneTap;

  const SessionDrawer({
    super.key,
    required this.sessions,
    this.activeSessionName,
    this.activeWindowIndex,
    this.activePaneId,
    this.onSessionTap,
    this.onWindowTap,
    this.onPaneTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return ExpansionTile(
          leading: Icon(
            Icons.folder,
            color: session.name == activeSessionName
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          title: Text(session.name),
          subtitle: Text('${session.windows.length} windows'),
          initiallyExpanded: session.name == activeSessionName,
          children: session.windows.map((window) {
            return ExpansionTile(
              leading: Icon(
                Icons.tab,
                color: session.name == activeSessionName &&
                        window.index == activeWindowIndex
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(window.name),
              subtitle: Text('${window.panes.length} panes'),
              children: window.panes.map((pane) {
                final isActive = pane.id == activePaneId;
                return ListTile(
                  leading: Icon(
                    Icons.terminal,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text('Pane ${pane.index}'),
                  subtitle: Text('${pane.width}x${pane.height}'),
                  selected: isActive,
                  onTap: () => onPaneTap?.call(pane.id),
                );
              }).toList(),
            );
          }).toList(),
        );
      },
    );
  }
}

class SessionItem {
  final String name;
  final List<WindowItem> windows;

  SessionItem({required this.name, required this.windows});
}

class WindowItem {
  final int index;
  final String name;
  final List<PaneItem> panes;

  WindowItem({required this.index, required this.name, required this.panes});
}

class PaneItem {
  final int index;
  final String id;
  final int width;
  final int height;

  PaneItem({
    required this.index,
    required this.id,
    required this.width,
    required this.height,
  });
}
