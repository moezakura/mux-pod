import 'package:flutter/material.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';

import 'package:flutter_muxpod/widgets/tmux_tiles.dart';

/// tmuxセッションツリー表示Widget
/// 仮想スクロール対応: ListView.builder + 遅延ウィジェット生成
class SessionTree extends StatelessWidget {
  final List<TmuxSession> sessions;
  final String? selectedPaneId;
  final void Function(String paneId)? onPaneSelected;
  final void Function(String sessionName)? onSessionDoubleTap;
  final void Function(TmuxPane pane)? onPaneResize;
  final void Function(String paneId)? onPaneClose;
  final void Function(TmuxWindow window)? onWindowResize;
  final void Function(String sessionName, int windowIndex, String windowName, bool isLastWindow)? onWindowClose;

  const SessionTree({
    super.key,
    required this.sessions,
    this.selectedPaneId,
    this.onPaneSelected,
    this.onSessionDoubleTap,
    this.onPaneResize,
    this.onPaneClose,
    this.onWindowResize,
    this.onWindowClose,
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
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        return _SessionTile(
          session: sessions[index],
          selectedPaneId: selectedPaneId,
          onPaneSelected: onPaneSelected,
          onSessionDoubleTap: onSessionDoubleTap,
          onPaneResize: onPaneResize,
          onPaneClose: onPaneClose,
          onWindowResize: onWindowResize,
          onWindowClose: onWindowClose,
        );
      },
    );
  }
}

/// セッションタイル（展開状態を管理して遅延生成）
class _SessionTile extends StatefulWidget {
  final TmuxSession session;
  final String? selectedPaneId;
  final void Function(String paneId)? onPaneSelected;
  final void Function(String sessionName)? onSessionDoubleTap;
  final void Function(TmuxPane pane)? onPaneResize;
  final void Function(String paneId)? onPaneClose;
  final void Function(TmuxWindow window)? onWindowResize;
  final void Function(String sessionName, int windowIndex, String windowName, bool isLastWindow)? onWindowClose;

  const _SessionTile({
    required this.session,
    this.selectedPaneId,
    this.onPaneSelected,
    this.onSessionDoubleTap,
    this.onPaneResize,
    this.onPaneClose,
    this.onWindowResize,
    this.onWindowClose,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        GestureDetector(
          onDoubleTap: () => widget.onSessionDoubleTap?.call(widget.session.name),
          child: TmuxSessionTile(
            session: widget.session,
            isActive: widget.session.attached,
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            trailing: Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        if (_isExpanded)
          ...widget.session.windows.map((window) {
            return _WindowTile(
              sessionName: widget.session.name,
              window: window,
              isLastWindow: widget.session.windows.length == 1,
              selectedPaneId: widget.selectedPaneId,
              onPaneSelected: widget.onPaneSelected,
              onPaneResize: widget.onPaneResize,
              onPaneClose: widget.onPaneClose,
              onWindowResize: widget.onWindowResize,
              onWindowClose: widget.onWindowClose,
            );
          }),
      ],
    );
  }
}

/// ウィンドウタイル（展開状態を管理して遅延生成）
class _WindowTile extends StatefulWidget {
  final String sessionName;
  final TmuxWindow window;
  final bool isLastWindow;
  final String? selectedPaneId;
  final void Function(String paneId)? onPaneSelected;
  final void Function(TmuxPane pane)? onPaneResize;
  final void Function(String paneId)? onPaneClose;
  final void Function(TmuxWindow window)? onWindowResize;
  final void Function(String sessionName, int windowIndex, String windowName, bool isLastWindow)? onWindowClose;

  const _WindowTile({
    required this.sessionName,
    required this.window,
    required this.isLastWindow,
    this.selectedPaneId,
    this.onPaneSelected,
    this.onPaneResize,
    this.onPaneClose,
    this.onWindowResize,
    this.onWindowClose,
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
      child: Column(
        children: [
          TmuxWindowTile(
            window: widget.window,
            isActive: widget.window.active,
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            onResize: widget.onWindowResize != null
                ? () => widget.onWindowResize!(widget.window)
                : null,
            onClose: widget.onWindowClose != null
                ? () => widget.onWindowClose?.call(
                      widget.sessionName,
                      widget.window.index,
                      widget.window.name,
                      widget.isLastWindow,
                    )
                : null,
          ),
          if (_isExpanded)
            ...widget.window.panes.map((pane) => _buildPaneNode(context, pane)),
        ],
      ),
    );
  }

  Widget _buildPaneNode(BuildContext context, TmuxPane pane) {
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: TmuxPaneTile(
        pane: pane,
        paneTitle: pane.title ?? 'Pane ${pane.index}',
        isActive: pane.id == widget.selectedPaneId,
        onTap: () => widget.onPaneSelected?.call(pane.id),
        onResize: widget.onPaneResize != null
            ? () => widget.onPaneResize!(pane)
            : null,
        onClose: widget.onPaneClose != null
            ? () => widget.onPaneClose!(pane.id)
            : null,
      ),
    );
  }
}
