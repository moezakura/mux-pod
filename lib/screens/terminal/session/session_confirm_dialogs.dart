// ペイン/ウィンドウの close 確認ダイアログ（UI 表示・mutation と分離）。
import 'package:flutter/material.dart';

import '../../../../providers/tmux_provider.dart';
import '../../../../theme/design_colors.dart';
import '../../../l10n/l10n_ext.dart';
import 'session_env.dart';
import 'session_runtime.dart';

/// 破壊的操作の確認 UI（TmuxSessionMutations から呼ばれ、実行を委譲する）。
class SessionConfirmDialogs {
  SessionConfirmDialogs(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  /// 確認後は [onConfirm]（killPane 実行）を呼ぶ。
  void confirmAndKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastWindow,
    required void Function() onConfirm,
  }) {
    final isDark = Theme.of(env.host.context).brightness == Brightness.dark;
    showDialog(
      context: env.host.context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            env.host.context.l10n.termClosePaneTitle,
            style: TextStyle(
              color: isDark
                  ? DesignColors.textPrimary
                  : DesignColors.textPrimaryLight,
            ),
          ),
          content: Text(
            isLastPane && isLastWindow
                ? env.host.context.l10n.termClosePaneLastWindowLastPane
                : isLastPane
                ? env.host.context.l10n.termClosePaneLastPane
                : env.host.context.l10n.termClosePaneConfirm(paneTitle),
            style: TextStyle(
              color: isDark
                  ? DesignColors.textSecondary
                  : DesignColors.textSecondaryLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                env.host.context.l10n.termCancel,
                style: TextStyle(
                  color: isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                final currentWindow = env.ref.read(tmuxProvider).activeWindow;
                if (currentWindow == null ||
                    !currentWindow.panes.any((p) => p.id == paneId)) {
                  if (env.host.isMounted) {
                    ScaffoldMessenger.of(env.host.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          env.host.context.l10n.termPaneNoLongerExists,
                        ),
                      ),
                    );
                  }
                  return;
                }
                onConfirm();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text(env.host.context.l10n.termClose),
            ),
          ],
        );
      },
    );
  }

  /// 確認後は [onConfirm]（killWindow 実行）を呼ぶ。
  void confirmAndKillWindow({
    required String sessionName,
    required int windowIndex,
    required String windowName,
    required bool isLastWindow,
    required void Function(bool wasActiveWindow) onConfirm,
  }) {
    final isDark = Theme.of(env.host.context).brightness == Brightness.dark;
    showDialog(
      context: env.host.context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            env.host.context.l10n.termCloseWindowTitle,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: Text(
            isLastWindow
                ? env.host.context.l10n.termCloseWindowLast
                : env.host.context.l10n.termCloseWindowConfirm(windowName),
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                env.host.context.l10n.termCancel,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                final wasActive =
                    windowIndex == env.ref.read(tmuxProvider).activeWindowIndex;
                onConfirm(wasActive);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text(env.host.context.l10n.termClose),
            ),
          ],
        );
      },
    );
  }
}
