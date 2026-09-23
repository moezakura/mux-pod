import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../services/backend/domain/multiplexer_backend.dart'
    show MultiplexerBackendKind;
import '../../services/backend/domain/multiplexer_session.dart'
    show MultiplexerSession;
import '../../theme/design_colors.dart';

/// カード展開時のセッション一覧パネル。
///
/// 元は `_ConnectionCardState._buildDomainExpandedContent`（private）。
/// **provider を watch しない** StatelessWidget。導出済みの値
/// （`liveWindowCounts`）とコールバックを props で受領する。
class ExpandedSessionsPanel extends StatelessWidget {
  final List<MultiplexerSession> sessions;

  /// アクティブセッション由来の最新ウィンドウ数（呼出側 State が導出）。
  final Map<String, int> liveWindowCounts;
  final bool isLoading;
  final String? sessionError;
  final MultiplexerBackendKind backendKind;
  final VoidCallback onReload;
  final VoidCallback onNewSession;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// セッション行タップ（Terminal を開く）。実際の遷移は呼出側が行う。
  final void Function(String sessionName, String? sessionId) onSessionTap;

  /// セッション行の Kill ボタン（tmux: kill / herdr: workspace close）。
  /// [isLoading] 中は無効化される。
  final void Function(MultiplexerSession session) onKill;

  const ExpandedSessionsPanel({
    super.key,
    required this.sessions,
    required this.liveWindowCounts,
    required this.isLoading,
    required this.sessionError,
    required this.backendKind,
    required this.onReload,
    required this.onNewSession,
    required this.onEdit,
    required this.onDelete,
    required this.onSessionTap,
    required this.onKill,
  });

  bool get _isHerdr => backendKind == MultiplexerBackendKind.herdr;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15161C) : const Color(0xFFF8F9FA),
        border: Border(
          top: BorderSide(
            color: isDark ? DesignColors.borderDark : DesignColors.borderLight,
          ),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sessions Section Header with Reload Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  context.l10n.connActiveSessions,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? DesignColors.textMuted
                        : DesignColors.textMutedLight,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(
                      Icons.refresh,
                      color: isDark
                          ? DesignColors.textMuted
                          : DesignColors.textMutedLight,
                    ),
                    onPressed: isLoading ? null : onReload,
                    tooltip: context.l10n.connReloadSessions,
                  ),
                ),
              ],
            ),
          ),
          // Sessions List
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (sessionError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                sessionError!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: DesignColors.error,
                ),
              ),
            )
          else if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _isHerdr
                    ? context.l10n.connNoWorkspacesFound
                    : context.l10n.connNoSessionsFound,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
              ),
            )
          else
            ..._buildSessionRows(context, colorScheme, isDark),
          // New Session / New Workspace ボタン（Q-05: herdr でも有効化）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: OutlinedButton.icon(
              onPressed: onNewSession,
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                _isHerdr
                    ? context.l10n.connNewWorkspace
                    : context.l10n.connNewSession,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.primary.withValues(alpha: 0.8),
                side: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  style: BorderStyle.solid,
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ),
          Divider(
            color: isDark ? DesignColors.borderDark : DesignColors.borderLight,
            height: 1,
          ),
          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: Text(context.l10n.connEdit),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? DesignColors.textSecondary
                          : DesignColors.textSecondaryLight,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 16),
                    label: Text(context.l10n.connDelete),
                    style: TextButton.styleFrom(
                      foregroundColor: DesignColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSessionRows(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return sessions.map((session) {
      final windowCount =
          liveWindowCounts[session.id ?? session.name] ?? session.windowCount;
      return SessionRow(
        session: session,
        windowCount: windowCount,
        onTap: () => onSessionTap(session.name, session.id),
        onKill: isLoading ? null : () => onKill(session),
        isHerdr: _isHerdr,
        colorScheme: colorScheme,
        isDark: isDark,
      );
    }).toList();
  }
}

/// 共通 domain のセッション行（terminal アイコン・名前・window 数・状態・Kill）。
///
/// 元は `_ConnectionCardState._buildDomainSessionItems`（private）。導出済みの
/// [windowCount] とコールバックを props で受領する。
class SessionRow extends StatelessWidget {
  final MultiplexerSession session;
  final int windowCount;
  final VoidCallback onTap;
  final VoidCallback? onKill;
  final bool isHerdr;
  final ColorScheme colorScheme;
  final bool isDark;

  const SessionRow({
    super.key,
    required this.session,
    required this.windowCount,
    required this.onTap,
    required this.onKill,
    required this.isHerdr,
    required this.colorScheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isAttached = session.attached;
    return InkWell(
      // タップで Terminal を開く（tmux / herdr とも mutation 可能な
      // TerminalScreen に遷移する・Q-05）
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.terminal,
              size: 16,
              color: isAttached
                  ? colorScheme.primary
                  : (isDark
                        ? DesignColors.textMuted
                        : DesignColors.textMutedLight),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.name,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    context.l10n.connWindowsCount(windowCount),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: isDark
                          ? DesignColors.textMuted
                          : DesignColors.textMutedLight,
                    ),
                  ),
                ],
              ),
            ),
            // Status Badge（Attached / Detached）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isAttached
                    ? (isDark
                          ? DesignColors.connectedCardDark.withValues(
                              alpha: 0.5,
                            )
                          : DesignColors.connectedCardLight)
                    : (isDark
                          ? DesignColors.borderDark
                          : DesignColors.borderLight),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isAttached
                      ? (isDark
                            ? DesignColors.connectedCardBorderDark.withValues(
                                alpha: 0.7,
                              )
                            : DesignColors.connectedCardBorderLight)
                      : (isDark
                            ? DesignColors.borderDark
                            : DesignColors.borderLight),
                ),
              ),
              child: Text(
                isAttached
                    ? context.l10n.connAttached
                    : context.l10n.connDetached,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isAttached
                      ? (isDark
                            ? DesignColors.connectedCardTextDark
                            : DesignColors.connectedCardTextLight)
                      : (isDark
                            ? DesignColors.textMuted
                            : DesignColors.textMutedLight),
                ),
              ),
            ),
            // Kill ボタン（tmux: Kill Session / herdr: Kill Workspace・Q-05）
            const SizedBox(width: 4),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: const Icon(Icons.delete, color: DesignColors.error),
                onPressed: onKill,
                tooltip: isHerdr
                    ? context.l10n.connKillWorkspaceTooltip
                    : context.l10n.connKillSessionTooltip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
