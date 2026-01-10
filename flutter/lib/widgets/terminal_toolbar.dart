import 'package:flutter/material.dart';

import '../services/ssh/ssh_client.dart';

/// ターミナルツールバーウィジェット
///
/// 接続状態、セッション操作ボタンを表示する。
class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.connectionName,
    required this.status,
    this.onSessionsTap,
    this.onDisconnect,
    this.onSettings,
  });

  final String connectionName;
  final ConnectionStatus status;
  final VoidCallback? onSessionsTap;
  final VoidCallback? onDisconnect;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // 接続状態インジケーター
          _buildStatusIndicator(context),
          const SizedBox(width: 8),

          // 接続名
          Expanded(
            child: Text(
              connectionName,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // セッション一覧ボタン
          if (status == ConnectionStatus.connected) ...[
            IconButton(
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: onSessionsTap,
              tooltip: 'Sessions',
              iconSize: 20,
            ),
          ],

          // 設定ボタン
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: onSettings,
            tooltip: 'Terminal Settings',
            iconSize: 20,
          ),

          // 切断ボタン
          IconButton(
            icon: Icon(
              status == ConnectionStatus.connected
                  ? Icons.link_off
                  : Icons.close,
              color: colorScheme.error,
            ),
            onPressed: onDisconnect,
            tooltip: status == ConnectionStatus.connected ? 'Disconnect' : 'Close',
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final Color color;
    final IconData icon;
    final bool animate;

    switch (status) {
      case ConnectionStatus.disconnected:
        color = colorScheme.outline;
        icon = Icons.circle_outlined;
        animate = false;
      case ConnectionStatus.connecting:
        color = colorScheme.tertiary;
        icon = Icons.sync;
        animate = true;
      case ConnectionStatus.authenticating:
        color = colorScheme.tertiary;
        icon = Icons.lock_open;
        animate = true;
      case ConnectionStatus.connected:
        color = Colors.green;
        icon = Icons.circle;
        animate = false;
      case ConnectionStatus.error:
        color = colorScheme.error;
        icon = Icons.error;
        animate = false;
    }

    Widget indicator = Icon(icon, size: 12, color: color);

    if (animate) {
      indicator = _AnimatedIndicator(child: indicator);
    }

    return indicator;
  }
}

/// アニメーション付きインジケーター
class _AnimatedIndicator extends StatefulWidget {
  const _AnimatedIndicator({required this.child});

  final Widget child;

  @override
  State<_AnimatedIndicator> createState() => _AnimatedIndicatorState();
}

class _AnimatedIndicatorState extends State<_AnimatedIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: widget.child,
    );
  }
}

/// セッションドロワーウィジェット
class SessionsDrawer extends StatelessWidget {
  const SessionsDrawer({
    super.key,
    required this.child,
    this.onSessionSelect,
    this.onWindowSelect,
    this.onPaneSelect,
    this.onNewSession,
    this.onNewWindow,
    this.onRenameSession,
    this.onKillSession,
  });

  final Widget child;
  final void Function(String sessionName)? onSessionSelect;
  final void Function(String sessionName, int windowIndex)? onWindowSelect;
  final void Function(String sessionName, int windowIndex, int paneIndex)? onPaneSelect;
  final VoidCallback? onNewSession;
  final void Function(String sessionName)? onNewWindow;
  final void Function(String sessionName)? onRenameSession;
  final void Function(String sessionName)? onKillSession;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      endDrawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Sessions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: onNewSession,
                      tooltip: 'New Session',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // セッション一覧のプレースホルダー
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No sessions available',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connect to see tmux sessions',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
