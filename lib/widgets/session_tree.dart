import 'package:flutter/material.dart';

/// tmuxセッションツリー表示Widget
/// 仮想スクロール対応: ListView.builder + 遅延ウィジェット生成
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
      // 画面外のウィジェットを破棄してメモリ節約
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        return _SessionTile(
          session: sessions[index],
          selectedPaneId: selectedPaneId,
          onPaneSelected: onPaneSelected,
          onSessionDoubleTap: onSessionDoubleTap,
        );
      },
    );
  }
}

/// セッションタイル（展開状態を管理して遅延生成）
class _SessionTile extends StatefulWidget {
  final SessionNode session;
  final String? selectedPaneId;
  final void Function(String paneId)? onPaneSelected;
  final void Function(String sessionName)? onSessionDoubleTap;

  const _SessionTile({
    required this.session,
    this.selectedPaneId,
    this.onPaneSelected,
    this.onSessionDoubleTap,
  });

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.session.attached;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => widget.onSessionDoubleTap?.call(widget.session.name),
      child: ExpansionTile(
        leading: Icon(
          Icons.folder,
          color: widget.session.attached
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        title: Row(
          children: [
            Text(widget.session.name),
            if (widget.session.attached)
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
        initiallyExpanded: widget.session.attached,
        onExpansionChanged: (expanded) {
          setState(() => _isExpanded = expanded);
        },
        // 展開時のみ子ウィジェットを生成（遅延生成でメモリ節約）
        children: _isExpanded
            ? widget.session.windows.map((window) {
                return _WindowTile(
                  sessionName: widget.session.name,
                  window: window,
                  selectedPaneId: widget.selectedPaneId,
                  onPaneSelected: widget.onPaneSelected,
                );
              }).toList()
            : const [],
      ),
    );
  }
}

/// ウィンドウタイル（展開状態を管理して遅延生成）
class _WindowTile extends StatefulWidget {
  final String sessionName;
  final WindowNode window;
  final String? selectedPaneId;
  final void Function(String paneId)? onPaneSelected;

  const _WindowTile({
    required this.sessionName,
    required this.window,
    this.selectedPaneId,
    this.onPaneSelected,
  });

  @override
  State<_WindowTile> createState() => _WindowTileState();
}

class _WindowTileState extends State<_WindowTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.window.active;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: ExpansionTile(
        leading: Icon(
          Icons.tab,
          color: widget.window.active
              ? Theme.of(context).colorScheme.secondary
              : null,
        ),
        title: Text('${widget.window.index}: ${widget.window.name}'),
        initiallyExpanded: widget.window.active,
        onExpansionChanged: (expanded) {
          setState(() => _isExpanded = expanded);
        },
        // 展開時のみ子ウィジェットを生成（遅延生成でメモリ節約）
        children: _isExpanded
            ? widget.window.panes.map((pane) {
                return _buildPaneNode(context, pane);
              }).toList()
            : const [],
      ),
    );
  }

  Widget _buildPaneNode(BuildContext context, PaneNode pane) {
    final isSelected = pane.id == widget.selectedPaneId;

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
        onTap: () => widget.onPaneSelected?.call(pane.id),
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
