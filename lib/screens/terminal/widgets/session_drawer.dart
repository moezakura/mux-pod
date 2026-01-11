import 'package:flutter/material.dart';

/// セッション/ウィンドウ/ペインを表示するドロワー
/// 仮想スクロール対応: ListView.builder + 遅延ウィジェット生成
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
      // 画面外のウィジェットを破棄してメモリ節約
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionTile(
          session: session,
          isActive: session.name == activeSessionName,
          activeWindowIndex: activeWindowIndex,
          activePaneId: activePaneId,
          onPaneTap: onPaneTap,
        );
      },
    );
  }
}

/// セッションタイル（展開状態を管理して遅延生成）
class _SessionTile extends StatefulWidget {
  final SessionItem session;
  final bool isActive;
  final int? activeWindowIndex;
  final String? activePaneId;
  final void Function(String paneId)? onPaneTap;

  const _SessionTile({
    required this.session,
    required this.isActive,
    this.activeWindowIndex,
    this.activePaneId,
    this.onPaneTap,
  });

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isActive;
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(
        Icons.folder,
        color: widget.isActive
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text(widget.session.name),
      subtitle: Text('${widget.session.windows.length} windows'),
      initiallyExpanded: widget.isActive,
      onExpansionChanged: (expanded) {
        setState(() => _isExpanded = expanded);
      },
      // 展開時のみ子ウィジェットを生成（遅延生成でメモリ節約）
      children: _isExpanded
          ? widget.session.windows.map((window) {
              return _WindowTile(
                window: window,
                isSessionActive: widget.isActive,
                activeWindowIndex: widget.activeWindowIndex,
                activePaneId: widget.activePaneId,
                onPaneTap: widget.onPaneTap,
              );
            }).toList()
          : const [],
    );
  }
}

/// ウィンドウタイル（展開状態を管理して遅延生成）
class _WindowTile extends StatefulWidget {
  final WindowItem window;
  final bool isSessionActive;
  final int? activeWindowIndex;
  final String? activePaneId;
  final void Function(String paneId)? onPaneTap;

  const _WindowTile({
    required this.window,
    required this.isSessionActive,
    this.activeWindowIndex,
    this.activePaneId,
    this.onPaneTap,
  });

  @override
  State<_WindowTile> createState() => _WindowTileState();
}

class _WindowTileState extends State<_WindowTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isSessionActive &&
        widget.window.index == widget.activeWindowIndex;
  }

  @override
  Widget build(BuildContext context) {
    final isActiveWindow = widget.isSessionActive &&
        widget.window.index == widget.activeWindowIndex;

    return ExpansionTile(
      leading: Icon(
        Icons.tab,
        color: isActiveWindow
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text(widget.window.name),
      subtitle: Text('${widget.window.panes.length} panes'),
      initiallyExpanded: isActiveWindow,
      onExpansionChanged: (expanded) {
        setState(() => _isExpanded = expanded);
      },
      // 展開時のみ子ウィジェットを生成（遅延生成でメモリ節約）
      children: _isExpanded
          ? widget.window.panes.map((pane) {
              final isActive = pane.id == widget.activePaneId;
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
                onTap: () => widget.onPaneTap?.call(pane.id),
              );
            }).toList()
          : const [],
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
