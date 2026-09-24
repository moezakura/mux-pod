// セッションツリー更新（session-tree・移設元 L1958-2009）。
import 'dart:async';

import '../../../../providers/active_session_provider.dart';
import '../../../../providers/ssh_provider.dart';
import '../../../../services/tmux/ssh_tmux_command_executor.dart';
import '../../../../providers/tmux_provider.dart';
import 'session_env.dart';
import 'session_runtime.dart';

/// 10 秒ごとのセッションツリー更新（`SessionRuntimeController` へ注入）。
class SessionTreeRefresher {
  SessionTreeRefresher(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  /// `_refreshSessionTree` の移設。
  Future<void> refreshSessionTree() async {
    if (env.host.isDisposed) {
      return;
    }
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null || !sshClient.isConnected) {
      return;
    }

    try {
      final sessions = await env.tmux.listAllPanes(sshClient.tmuxExecutor);
      if (!env.host.isMounted || env.host.isDisposed) return;
      env.ref.read(tmuxProvider.notifier).updateSessions(sessions);
      final refreshedSession = env.ref.read(tmuxProvider).activeSession;
      if (refreshedSession != null) {
        env.ref
            .read(activeSessionsProvider.notifier)
            .updateWindowCount(
              env.host.connectionId,
              refreshedSession.name,
              refreshedSession.windows.length,
              sessionId: refreshedSession.id,
            );
      }
    } catch (_) {
      // ツリー更新エラーは静かに無視（次回ポーリングで再試行）
    }
  }

  /// 10 秒ごとのツリー更新開始（`_startTreeRefresh`）。
  void startTreeRefresh() {
    runtime.treeRefreshTimer?.cancel();
    runtime.treeRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!runtime.isPolling) {
        refreshSessionTree();
      }
    });
  }
}
