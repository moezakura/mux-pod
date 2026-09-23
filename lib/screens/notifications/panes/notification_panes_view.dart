import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../providers/active_session_provider.dart';
import '../../../providers/notification_panes_provider.dart';
import '../../../l10n/l10n_ext.dart';

import '../../../theme/design_colors.dart';
import '../../terminal/terminal_screen.dart';

import 'alert_pane_card.dart';

/// 通知ペイン一覧画面（tmuxのactivity/bell/silenceフラグベース）。
///
/// 単一の状態所有者（`_isRefreshing`・refresh 開始・解放オーケストレーション
/// を保持する State）と、表示部品 [AlertPaneCard] への合成を行う画面ルート。
class NotificationPanesScreen extends ConsumerStatefulWidget {
  const NotificationPanesScreen({super.key});

  @override
  ConsumerState<NotificationPanesScreen> createState() =>
      _NotificationPanesScreenState();
}

class _NotificationPanesScreenState
    extends ConsumerState<NotificationPanesScreen> {
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

    ref
        .read(activeSessionsProvider.notifier)
        .addOrUpdateSession(
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
                child: _buildEmptyState(context, isDark),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final alert = alertState.alertPanes[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AlertPaneCard(
                        alert: alert,
                        onTap: () => _openAlertPane(alert),
                        onDismiss: () => _dismissAlert(alert),
                      ),
                    );
                  }, childCount: alertState.alertPanes.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    bool isDark,
    ColorScheme colorScheme,
  ) {
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
          context.l10n.notifAlerts,
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
                    color: isDark
                        ? DesignColors.textSecondary
                        : DesignColors.textSecondaryLight,
                  ),
                )
              : Icon(
                  Icons.refresh,
                  color: isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight,
                ),
          onPressed: _isRefreshing ? null : _refresh,
          tooltip: context.l10n.notifRefreshAlerts,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.notifNoAlerts,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? DesignColors.textSecondary
                  : DesignColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.notifAllPanesQuiet,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark
                  ? DesignColors.textMuted
                  : DesignColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }
}
