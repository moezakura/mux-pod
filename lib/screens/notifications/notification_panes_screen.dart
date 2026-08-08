import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/active_session_provider.dart';
import '../../providers/notification_panes_provider.dart';
import '../../services/tmux/tmux_models.dart';

import '../../theme/design_colors.dart';
import '../terminal/terminal_screen.dart';

/// 通知ペイン一覧画面（tmuxのactivity/bell/silenceフラグベース）
class NotificationPanesScreen extends ConsumerStatefulWidget {
  const NotificationPanesScreen({super.key});

  @override
  ConsumerState<NotificationPanesScreen> createState() => _NotificationPanesScreenState();
}

class _NotificationPanesScreenState extends ConsumerState<NotificationPanesScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await ref.read(alertPanesProvider.notifier).refresh();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _openAlertPane(AlertPane alert) async {
    final notifier = ref.read(alertPanesProvider.notifier);

    // ローカルリストから同一ウィンドウのアラートを除去
    final windowKey = alert.windowKey;
    final currentPanes = ref.read(alertPanesProvider).alertPanes;
    for (final a in currentPanes) {
      if (a.windowKey == windowKey) {
        notifier.dismiss(a.key);
      }
    }

    // tmux側のウィンドウフラグをクリア（バックグラウンド）
    notifier.clearWindowFlag(alert);

    ref.read(activeSessionsProvider.notifier).addOrUpdateSession(
      connectionId: alert.connectionId,
      connectionName: alert.connectionName,
      host: alert.host,
      sessionName: alert.sessionName,
      sessionId: alert.sessionId,
      windowCount: 0,
      isAttached: true,
      lastWindowIndex: alert.windowIndex,
      lastPaneId: alert.paneId,
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          connectionId: alert.connectionId,
          sessionName: alert.sessionName,
          sessionId: alert.sessionId,
          lastWindowIndex: alert.windowIndex,
          lastPaneId: alert.paneId,
        ),
      ),
    );
  }

  void _dismissAlert(AlertPane alert) {
    final notifier = ref.read(alertPanesProvider.notifier);
    notifier.dismiss(alert.key);
    // tmux側のフラグもクリア
    notifier.clearWindowFlag(alert);
  }

  @override
  Widget build(BuildContext context) {
    final alertState = ref.watch(alertPanesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: DesignColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(context, isDark, colorScheme),
            if (alertState.isLoading && alertState.alertPanes.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (alertState.alertPanes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(isDark),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final alert = alertState.alertPanes[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AlertPaneCard(
                          alert: alert,
                          onTap: () => _openAlertPane(alert),
                          onDismiss: () => _dismissAlert(alert),
                        ),
                      );
                    },
                    childCount: alertState.alertPanes.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDark, ColorScheme colorScheme) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 100,
      backgroundColor: isDark
          ? DesignColors.backgroundDark.withValues(alpha: 0.95)
          : DesignColors.backgroundLight.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
        title: Text(
          'Alerts',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: _isRefreshing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
                  ),
                )
              : Icon(
                  Icons.refresh,
                  color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
                ),
          onPressed: _isRefreshing ? null : _refresh,
          tooltip: 'Refresh alerts',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
          ),
          const SizedBox(height: 16),
          Text(
            'No alerts',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All panes are quiet',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }
}

/// アラートペインカード
class _AlertPaneCard extends StatelessWidget {
  final AlertPane alert;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _AlertPaneCard({
    required this.alert,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: Key(alert.key),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: DesignColors.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.notifications_off,
              color: DesignColors.error,
            ),
            const SizedBox(height: 4),
            Text(
              'Dismiss',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: DesignColors.error,
              ),
            ),
          ],
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? DesignColors.borderDark : DesignColors.borderLight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Flag Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _flagBackgroundColor(alert.primaryFlag, isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _flagBorderColor(alert.primaryFlag, isDark),
                  ),
                ),
                child: Icon(
                  _flagIcon(alert.primaryFlag),
                  size: 24,
                  color: _flagIconColor(alert.primaryFlag),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.connectionName}: ${alert.sessionName}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.host,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'W${alert.windowIndex}: ${alert.windowName}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                          ),
                        ),
                        Text(
                          ' • Pane ${alert.paneIndex}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                          ),
                        ),
                        if (alert.currentCommand != null) ...[
                          Text(
                            ' • ',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              alert.currentCommand!,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Flag Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _flagBadgeBackground(alert.primaryFlag, isDark),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _flagBadgeBorder(alert.primaryFlag, isDark),
                  ),
                ),
                child: Text(
                  _flagLabel(alert.primaryFlag),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _flagIconColor(alert.primaryFlag),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _flagIcon(TmuxWindowFlag? flag) {
    return switch (flag) {
      TmuxWindowFlag.bell => Icons.notifications_active,
      TmuxWindowFlag.activity => Icons.trending_up,
      TmuxWindowFlag.silence => Icons.notifications_off,
      _ => Icons.notifications_outlined,
    };
  }

  Color _flagIconColor(TmuxWindowFlag? flag) {
    return switch (flag) {
      TmuxWindowFlag.bell => DesignColors.error,
      TmuxWindowFlag.activity => Colors.orange,
      TmuxWindowFlag.silence => Colors.grey,
      _ => Colors.grey,
    };
  }

  Color _flagBackgroundColor(TmuxWindowFlag? flag, bool isDark) {
    return switch (flag) {
      TmuxWindowFlag.bell => DesignColors.error.withValues(alpha: isDark ? 0.15 : 0.1),
      TmuxWindowFlag.activity => Colors.orange.withValues(alpha: isDark ? 0.15 : 0.1),
      TmuxWindowFlag.silence => Colors.grey.withValues(alpha: isDark ? 0.15 : 0.1),
      _ => isDark ? DesignColors.borderDark : DesignColors.borderLight,
    };
  }

  Color _flagBorderColor(TmuxWindowFlag? flag, bool isDark) {
    return switch (flag) {
      TmuxWindowFlag.bell => DesignColors.error.withValues(alpha: 0.3),
      TmuxWindowFlag.activity => Colors.orange.withValues(alpha: 0.3),
      TmuxWindowFlag.silence => Colors.grey.withValues(alpha: 0.3),
      _ => Colors.transparent,
    };
  }

  Color _flagBadgeBackground(TmuxWindowFlag? flag, bool isDark) {
    return switch (flag) {
      TmuxWindowFlag.bell => DesignColors.error.withValues(alpha: isDark ? 0.2 : 0.1),
      TmuxWindowFlag.activity => Colors.orange.withValues(alpha: isDark ? 0.2 : 0.1),
      TmuxWindowFlag.silence => Colors.grey.withValues(alpha: isDark ? 0.2 : 0.1),
      _ => isDark ? DesignColors.borderDark : DesignColors.borderLight,
    };
  }

  Color _flagBadgeBorder(TmuxWindowFlag? flag, bool isDark) {
    return switch (flag) {
      TmuxWindowFlag.bell => DesignColors.error.withValues(alpha: isDark ? 0.4 : 0.3),
      TmuxWindowFlag.activity => Colors.orange.withValues(alpha: isDark ? 0.4 : 0.3),
      TmuxWindowFlag.silence => Colors.grey.withValues(alpha: isDark ? 0.4 : 0.3),
      _ => isDark ? DesignColors.borderDark : DesignColors.borderLight,
    };
  }

  String _flagLabel(TmuxWindowFlag? flag) {
    return switch (flag) {
      TmuxWindowFlag.bell => 'Bell',
      TmuxWindowFlag.activity => 'Activity',
      TmuxWindowFlag.silence => 'Silence',
      _ => 'Alert',
    };
  }
}
