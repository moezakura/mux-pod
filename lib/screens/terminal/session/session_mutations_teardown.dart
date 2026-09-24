// tmux の破壊的 mutation（session-mutations-teardown・移設元 L5600-6375 /
// L6804-6866）。killPane/killWindow/renameWindow の実行と確認 UI の配線。
// 確認 UI の表示本体は [SessionConfirmDialogs] が担う。
import 'package:flutter/material.dart';

import '../../../../providers/ssh_provider.dart';
import '../../../../providers/tmux_provider.dart';
import '../../../../services/backend/domain/pane_writer.dart';
import '../../../../services/tmux/tmux_contract.dart'
    show TmuxOutputParseException;
import '../../../../services/tmux/tmux_models.dart';
import '../../../../services/tmux/ssh_tmux_command_executor.dart';
import '../../../../widgets/dialogs/rename_window_dialog.dart';
import '../../../l10n/l10n_ext.dart';
import 'session_confirm_dialogs.dart';
import 'session_connection.dart';
import 'session_env.dart';
import 'session_mutations.dart';
import 'session_runtime.dart';

/// ペイン/ウィンドウ kill・リネーム の実行と確認配線。
class TmuxSessionTeardown {
  TmuxSessionTeardown(
    this.env,
    this.runtime, {
    required SessionConnectionFlow connection,
    required SessionConfirmDialogs dialogs,
    required TmuxSessionMutations mutations,
  }) : _connection = connection,
       _dialogs = dialogs,
       _mutations = mutations;

  final SessionEnv env;
  final SessionRuntimeController runtime;
  final SessionConnectionFlow _connection;
  final SessionConfirmDialogs _dialogs;
  final TmuxSessionMutations _mutations;

  void confirmAndKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastWindow,
  }) {
    _dialogs.confirmAndKillPane(
      paneId: paneId,
      paneTitle: paneTitle,
      isLastPane: isLastPane,
      isLastWindow: isLastWindow,
      onConfirm: () {
        killPane(
          paneId: paneId,
          isLastPane: isLastPane,
          isLastWindow: isLastWindow,
        );
      },
    );
  }

  Future<void> killPane({
    required String paneId,
    required bool isLastPane,
    required bool isLastWindow,
  }) async {
    if (!runtime.can(const PaneCapabilities(close: true))) return;
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (env.host.isMounted) {
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(content: Text(env.host.context.l10n.termSshNotAvailable)),
        );
      }
      return;
    }

    final writer = runtime.paneWriter;
    if (writer == null) return;

    runtime.pollTimer?.cancel();

    try {
      await writer.closePane(paneId);
      await runtime.refreshSessionTree?.call();
      if (!env.host.isMounted || env.host.isDisposed) return;

      if (isLastPane && isLastWindow) {
        var sessions = <TmuxSession>[];
        var listed = true;
        try {
          sessions = await env.tmux.listSessions(sshClient.tmuxExecutor);
        } on TmuxOutputParseException {
          listed = false;
        } catch (_) {}
        if (!env.host.isMounted || env.host.isDisposed) return;
        if (listed && sessions.isEmpty) {
          // ignore: use_build_context_synchronously
          await _connection.disconnect(env.host.context);
          return;
        }
      }

      if (isLastPane) {
        final newTmuxState = env.ref.read(tmuxProvider);
        final newSession = newTmuxState.activeSession;
        if (newSession != null) {
          final newActiveWindow =
              newSession.windows.where((w) => w.active).firstOrNull ??
              newSession.windows.firstOrNull;
          if (newActiveWindow != null) {
            await _mutations.selectWindow(
              newSession.name,
              newActiveWindow.index,
            );
          }
        }
      } else {
        final newTmuxState = env.ref.read(tmuxProvider);
        final activeWindow = newTmuxState.activeWindow;
        if (activeWindow != null) {
          final newActivePane =
              activeWindow.panes.where((p) => p.active).firstOrNull ??
              activeWindow.panes.firstOrNull;
          if (newActivePane != null) {
            await _mutations.selectPane(newActivePane.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[Terminal] Failed to kill pane: $e');
      if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(
              env.host.context.l10n.termFailedToClosePane(e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (env.host.isMounted && !env.host.isDisposed) {
        runtime.startPolling();
      }
    }
  }

  void confirmAndKillWindow({
    required String sessionName,
    required int windowIndex,
    required String windowName,
    required bool isLastWindow,
  }) {
    _dialogs.confirmAndKillWindow(
      sessionName: sessionName,
      windowIndex: windowIndex,
      windowName: windowName,
      isLastWindow: isLastWindow,
      onConfirm: (wasActive) {
        killWindow(
          sessionName: sessionName,
          windowIndex: windowIndex,
          wasActiveWindow: wasActive,
        );
      },
    );
  }

  Future<void> killWindow({
    required String sessionName,
    required int windowIndex,
    required bool wasActiveWindow,
  }) async {
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (env.host.isMounted) {
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(content: Text(env.host.context.l10n.termSshNotAvailable)),
        );
      }
      return;
    }

    try {
      debugPrint('[Terminal] Killing window: $sessionName:$windowIndex');
      await env.tmux.killWindow(
        sshClient.tmuxExecutor,
        sessionName,
        windowIndex,
      );
      await runtime.refreshSessionTree?.call();

      if (!env.host.isMounted || env.host.isDisposed) return;

      var sessions = <TmuxSession>[];
      var listed = true;
      try {
        sessions = await env.tmux.listSessions(sshClient.tmuxExecutor);
      } on TmuxOutputParseException {
        listed = false;
      } catch (_) {}
      if (listed && sessions.isEmpty) {
        debugPrint(
          '[Terminal] Last window closed, session terminated. Disconnecting...',
        );
        // ignore: use_build_context_synchronously
        await _connection.disconnect(env.host.context);
        return;
      }

      if (wasActiveWindow) {
        final newTmuxState = env.ref.read(tmuxProvider);
        final newSession = newTmuxState.activeSession;
        if (newSession != null) {
          final newActiveWindow =
              newSession.windows.where((w) => w.active).firstOrNull ??
              newSession.windows.firstOrNull;
          if (newActiveWindow != null) {
            await _mutations.selectWindow(
              newSession.name,
              newActiveWindow.index,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Terminal] Failed to kill window: $e');
      if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(
              env.host.context.l10n.termFailedToCloseWindow(e.toString()),
            ),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // リネーム（`_showRenameWindowDialog` / `_renameWindow`）
  // ---------------------------------------------------------------------------

  void showRenameWindowDialog(Object sessionObject, Object windowObject) {
    final session = sessionObject as TmuxSession;
    final window = windowObject as TmuxWindow;
    final otherNames = session.windows
        .where((w) => w.index != window.index)
        .map((w) => w.name)
        .toList();
    showDialog<String>(
      context: env.host.context,
      builder: (dialogContext) => RenameWindowDialog(
        currentName: window.name,
        otherWindowNames: otherNames,
      ),
    ).then((newName) {
      if (newName == null) return;
      final trimmed = newName.trim();
      if (trimmed.isEmpty || trimmed == window.name) return;
      renameWindow(
        sessionName: session.name,
        windowIndex: window.index,
        newName: trimmed,
      );
    });
  }

  Future<void> renameWindow({
    required String sessionName,
    required int windowIndex,
    required String newName,
  }) async {
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      if (env.host.isMounted) {
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(content: Text(env.host.context.l10n.termSshNotAvailable)),
        );
      }
      return;
    }
    try {
      debugPrint(
        '[Terminal] Renaming window: $sessionName:$windowIndex -> $newName',
      );
      await env.tmux.renameWindow(
        sshClient.tmuxExecutor,
        sessionName,
        windowIndex,
        newName,
      );
      await runtime.refreshSessionTree?.call();
    } catch (e) {
      debugPrint('[Terminal] Failed to rename window: $e');
      if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(
              env.host.context.l10n.termFailedToRenameWindow(e.toString()),
            ),
          ),
        );
      }
    }
  }
}
