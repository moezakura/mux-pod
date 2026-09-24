// tmux の mutation 実行（session-mutations・移設元 L3995-4329 / L5440-5682 /
// L6300-6375 / L6804-6866）。herdr 分岐は `SessionHerdrPort` へ委譲。
// 確認 UI（confirmAndKill*）は [SessionConfirmDialogs] に分離。
import 'package:flutter/material.dart';

import '../../../../providers/active_session_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/ssh_provider.dart';
import '../../../../providers/tmux_provider.dart';
import '../../../../providers/terminal_display_provider.dart';
import '../../../../services/backend/domain/multiplexer_backend.dart'
    show MultiplexerBackendKind;
import '../../../../services/backend/domain/pane_writer.dart';
import '../../../../services/tmux/commands/layout.dart' show SplitDirection;
import '../../../../services/tmux/tmux_models.dart';
import '../../../../services/tmux/ssh_tmux_command_executor.dart';
import '../../../../widgets/dialogs/new_window_dialog.dart';
import '../../../l10n/l10n_ext.dart';
import 'session_env.dart';
import 'session_runtime.dart';

/// tmux セッション/ウィンドウ/ペインの mutation（select/create/kill/rename）。
class TmuxSessionMutations {
  TmuxSessionMutations(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  // ---------------------------------------------------------------------------
  // セッション選択（`_selectSession`）
  // ---------------------------------------------------------------------------

  Future<void> selectSession(String sessionName) async {
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    env.ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

    final activePaneId = env.ref.read(tmuxProvider).activePaneId;
    if (activePaneId != null) {
      await selectPane(activePaneId);
    } else {
      runtime.viewNotifier.value = runtime.viewNotifier.value.copyWith(
        content: '',
      );
      runtime.hasInitialScrolled = false;
    }
  }

  // ---------------------------------------------------------------------------
  // ウィンドウ選択（`_selectWindow`）
  // ---------------------------------------------------------------------------

  Future<void> selectWindow(String sessionName, int windowIndex) async {
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    final currentSession = env.ref.read(tmuxProvider).activeSessionName;
    if (currentSession != sessionName) {
      env.ref.read(tmuxProvider.notifier).setActiveSession(sessionName);
    }

    try {
      await env.tmux.selectWindow(
        sshClient.tmuxExecutor,
        sessionName,
        windowIndex,
      );
    } catch (e) {
      debugPrint('[Terminal] Failed to select window: $e');
      return;
    }
    if (!env.host.isMounted || env.host.isDisposed) return;

    env.ref.read(tmuxProvider.notifier).setActiveWindow(windowIndex);

    final activePaneId = env.ref.read(tmuxProvider).activePaneId;
    if (activePaneId != null) {
      await selectPane(activePaneId);
    } else {
      runtime.viewNotifier.value = runtime.viewNotifier.value.copyWith(
        content: '',
      );
      runtime.hasInitialScrolled = false;
    }
  }

  // ---------------------------------------------------------------------------
  // ペイン選択（`_selectPane`・tmux 専用経路）
  // ---------------------------------------------------------------------------

  Future<void> selectPane(String paneId) async {
    if (!runtime.can(const PaneCapabilities(focus: true))) return;
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) return;

    env.input.selectPaneReset();

    final writer = runtime.paneWriter;
    if (writer == null) return;

    try {
      await writer.selectPane(paneId);
    } catch (e) {
      debugPrint('[Terminal] Failed to select pane: $e');
      return;
    }
    if (!env.host.isMounted || env.host.isDisposed) return;

    env.ref.read(tmuxProvider.notifier).setActivePane(paneId);

    final activePane = env.ref.read(tmuxProvider).activePane;
    final tmuxState = env.ref.read(tmuxProvider);
    if (activePane != null) {
      env.ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      runtime.viewNotifier.value = runtime.viewNotifier.value.copyWith(
        paneWidth: activePane.width,
        paneHeight: activePane.height,
        content: '',
      );
      runtime.hasInitialScrolled = false;

      if (env.ref.read(settingsProvider).isAutoResize) {
        final fn = runtime.executeAutoResize;
        if (fn != null) {
          await fn(activePane);
        }
      }

      final sessionName = tmuxState.activeSessionName;
      final sessionId = tmuxState.activeSession?.id;
      final windowIndex = tmuxState.activeWindowIndex;
      if (sessionName != null && windowIndex != null) {
        env.ref
            .read(activeSessionsProvider.notifier)
            .updateLastPane(
              connectionId: env.host.connectionId,
              sessionName: sessionName,
              sessionId: sessionId,
              windowIndex: windowIndex,
              paneId: paneId,
            );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ウィンドウ作成（`_showCreateWindowDialog` / `_createWindow` / `_sendNewWindowCommand`）
  // ---------------------------------------------------------------------------

  void showCreateWindowDialog(Object session) {
    final s = session as TmuxSession;
    final existingNames = s.windows.map((w) => w.name).toList();
    showDialog<NewWindowRequest>(
      context: env.host.context,
      builder: (dialogContext) =>
          NewWindowDialog(existingWindowNames: existingNames),
    ).then((request) {
      if (request != null) {
        createWindow(request);
      }
    });
  }

  Future<void> createWindow(Object requestObject) async {
    final request = requestObject as NewWindowRequest;
    if (runtime.isCreatingWindow) return;
    runtime.isCreatingWindow = true;
    try {
      final sshClient = env.ref.read(sshProvider.notifier).client;
      if (sshClient == null || !sshClient.isConnected) {
        if (env.host.isMounted) {
          ScaffoldMessenger.of(env.host.context).showSnackBar(
            SnackBar(content: Text(env.host.context.l10n.termSshNotAvailable)),
          );
        }
        return;
      }
      final session = env.ref.read(tmuxProvider).activeSession;
      if (session == null) return;

      await env.tmux.createWindow(
        sshClient.tmuxExecutor,
        sessionName: session.name,
        windowName: request.name,
      );
      await runtime.refreshSessionTree?.call();
      if (!env.host.isMounted) return;

      final command = request.command;
      var commandDispatched = false;

      final updatedSession = env.ref.read(tmuxProvider).activeSession;
      final activeWindow = updatedSession?.windows
          .where((w) => w.active)
          .firstOrNull;
      if (activeWindow != null) {
        env.ref.read(tmuxProvider.notifier).setActiveWindow(activeWindow.index);
        runtime.viewNotifier.value = runtime.viewNotifier.value.copyWith(
          content: '',
        );
        runtime.hasInitialScrolled = false;
        final activePaneId = env.ref.read(tmuxProvider).activePaneId;
        if (activePaneId != null) {
          await selectPane(activePaneId);
          if (command != null) {
            if (!env.host.isMounted) return;
            commandDispatched = true;
            await _sendNewWindowCommand(activePaneId, command);
          }
        }
      }
      if (command != null && !commandDispatched && env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(
              env.host.context.l10n.termWindowCreatedCommandNotSent,
            ),
          ),
        );
      }
      runtime.boostPolling();
    } catch (e) {
      if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(
              env.host.context.l10n.termFailedToCreateWindow(e.toString()),
            ),
          ),
        );
      }
    } finally {
      runtime.isCreatingWindow = false;
    }
  }

  Future<void> _sendNewWindowCommand(String paneId, String command) async {
    if (!runtime.canSendText) return;
    final writer = runtime.paneWriter;
    if (writer == null) return;
    try {
      await writer.sendText(paneId, command);
      await writer.sendKey(paneId, 'Enter');
    } catch (e) {
      if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(
              env.host.context.l10n.termWindowCreatedCommandFailed(
                e.toString(),
              ),
            ),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ペイン分割（`_splitPane`・tmux/herdr 分岐）
  // ---------------------------------------------------------------------------

  Future<void> splitPane(String paneId, Object directionObject) async {
    final direction = directionObject as SplitDirection;
    if (!runtime.canSplitPane) return;
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

    try {
      final directionName = switch (direction) {
        SplitDirection.horizontal => 'right',
        SplitDirection.vertical => 'down',
      };
      await writer.splitPane(paneId, directionName);
      if (runtime.backendKind == MultiplexerBackendKind.herdr) {
        await env.herdr.syncAfterHerdrMutation(eventLabel: 'split pane sync');
      } else {
        await runtime.refreshSessionTree?.call();
      }
    } catch (e) {
      if (runtime.backendKind == MultiplexerBackendKind.herdr) {
        await env.herdr.handleHerdrMutationError(e, operationLabel: 'split');
      } else if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(
              env.host.context.l10n.termFailedToSplitPane(e.toString()),
            ),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ペイン/ウィンドウ kill（確認 UI は SessionConfirmDialogs へ委譲）
  // ---------------------------------------------------------------------------
}
