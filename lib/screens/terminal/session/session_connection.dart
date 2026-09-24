// 接続〜切断〜再接続のフロー（session-connection・移設元 L1200-1520 / L3107-3125 /
// L3126 / L3150 / L6867-7275）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../providers/connection_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/ssh_provider.dart';
import '../../../../providers/terminal_display_provider.dart';
import '../../../../services/backend/backend_type.dart';
import '../../../../services/backend/domain/multiplexer_backend.dart';
import '../../../../services/keychain/secure_storage.dart';
import '../../../../services/ssh/ssh_client.dart';
import '../../../../services/tmux/ssh_tmux_command_executor.dart';
import '../../../../services/tmux/tmux_models.dart';
import '../../../../providers/tmux_provider.dart';
import '../../../../theme/design_colors.dart';
import '../../../l10n/l10n_ext.dart';
import '../target_source.dart';
import 'session_env.dart';
import 'session_runtime.dart';

/// 接続・切断・再接続の実行（SessionRuntimeController の collaboration）。
class SessionConnectionFlow {
  SessionConnectionFlow(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  final SecureStorageService _secureStorage = SecureStorageService();

  // ---------------------------------------------------------------------------
  // 初回接続（`_connectAndSetup`・移設元 L1254-1520）
  // ---------------------------------------------------------------------------

  Future<void> connectAndSetup() async {
    if (!env.host.isMounted) {
      return;
    }
    env.host.markNeedsBuild();
    runtime.isConnecting = true;
    runtime.connectionError = null;

    try {
      // 1. 接続情報を取得
      final connection = env.ref
          .read(connectionsProvider.notifier)
          .getById(env.host.connectionId);
      if (connection == null) {
        throw Exception('Connection not found');
      }

      // 1.5. backend 種別を確定
      final isHerdr = connection.multiplexer.backend == BackendType.herdr;
      runtime.backendKind = isHerdr
          ? MultiplexerBackendKind.herdr
          : MultiplexerBackendKind.tmux;

      // 2. 認証情報を取得
      final options = await _getAuthOptions(connection);
      if (!env.host.isMounted || env.host.isDisposed) {
        return;
      }

      // 3. SSH接続（シェルは起動しない - execのみ使用）
      final sshNotifier = env.ref.read(sshProvider.notifier);
      await sshNotifier.connectWithoutShell(connection, options);
      if (!env.host.isMounted || env.host.isDisposed) {
        return;
      }

      final client = sshNotifier.client;
      if (client == null) {
        throw Exception('SSH client is not available');
      }

      // モードリセット
      env.input.resetTerminalMode();

      // 3.4. herdr: セッションを設定して終了
      if (isHerdr) {
        await unselectedHerdrSetup(client);
        if (!env.host.isMounted || env.host.isDisposed) return;
        env.host.markNeedsBuild();
        runtime.isConnecting = false;
        return;
      }

      // 3.5. tmuxバージョン取得
      try {
        runtime.tmuxVersion = await env.tmux.getVersion(client.tmuxExecutor);
      } catch (_) {
        runtime.tmuxVersion = null;
      }

      // tmux のペイン内容読み取りを設定
      runtime.recreatePaneReader?.call();
      if (runtime.paneReader == null) {
        throw Exception('Pane content reader is not available');
      }

      // 4. セッションツリー全体を取得
      await runtime.refreshSessionTree?.call();
      if (!env.host.isMounted || env.host.isDisposed) {
        return;
      }

      final tmuxState = env.ref.read(tmuxProvider);
      final sessions = tmuxState.sessions;

      // 5. セッションを選択または新規作成
      String sessionName;
      if (env.host.sessionName != null) {
        final existingIndex = sessions.indexWhere(
          (s) => s.name == env.host.sessionName,
        );
        if (existingIndex >= 0) {
          sessionName = sessions[existingIndex].name;
        } else {
          final sshClient = env.ref.read(sshProvider.notifier).client;
          if (sshClient != null) {
            await env.tmux.createSession(
              sshClient.tmuxExecutor,
              name: env.host.sessionName!,
              detached: true,
            );
          }
          if (!env.host.isMounted || env.host.isDisposed) return;
          await runtime.refreshSessionTree?.call();
          if (!env.host.isMounted || env.host.isDisposed) return;
          sessionName = env.host.sessionName!;
        }
      } else if (sessions.isNotEmpty) {
        sessionName = sessions.first.name;
      } else {
        final sshClient = env.ref.read(sshProvider.notifier).client;
        sessionName = 'muxpod-${DateTime.now().millisecondsSinceEpoch}';
        if (sshClient != null) {
          await env.tmux.createSession(
            sshClient.tmuxExecutor,
            name: sessionName,
            detached: true,
          );
        }
        if (!env.host.isMounted || env.host.isDisposed) return;
        await runtime.refreshSessionTree?.call();
        if (!env.host.isMounted || env.host.isDisposed) return;
      }

      // このセッションの履歴保持行数を設定する（ベストエフォート）
      try {
        final historyLimit = env.ref
            .read(settingsProvider)
            .scrollbackLines
            .clamp(200, 20000)
            .toInt();
        final client = sshNotifier.client;
        if (client != null) {
          await env.tmux.setHistoryLimit(
            client.tmuxExecutor,
            historyLimit,
            target: sessionName,
          );
        }
      } catch (_) {}

      // 6. アクティブセッション/ウィンドウ/ペインを設定
      env.ref.read(tmuxProvider.notifier).setActiveSession(sessionName);

      // 6.1 ディープリンクまたは保存されたウィンドウ/ペイン位置を復元
      _restoreWindowPanePosition(sshNotifier);

      // 7. TerminalDisplayProviderにペイン情報を通知
      final activePane = env.ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        debugPrint(
          '[Terminal] Pane size: ${activePane.width}x${activePane.height}',
        );
        env.ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
        runtime.viewNotifier.value = runtime.viewNotifier.value.copyWith(
          paneWidth: activePane.width,
          paneHeight: activePane.height,
        );

        final client = sshNotifier.client;
        if (client != null) {
          await env.tmux.sendFocusIn(client.tmuxExecutor, activePane.id);
        }
      }

      // 7.5. 表示対象ソースを確定
      runtime.targetSource = TmuxTargetSource(
        () => env.ref.read(tmuxProvider.notifier).currentTarget,
      );

      // 8~9. ポーリングとツリー更新開始
      runtime.startPolling();
      runtime.startTreeRefresh?.call();

      if (!env.host.isMounted) return;
      env.host.markNeedsBuild();
      runtime.isConnecting = false;

      // 10. 自動リサイズ
      if (env.ref.read(settingsProvider).isAutoResize) {
        runtime.scheduleInitialAutoResize?.call();
      }
    } on SshAuthenticationError {
      if (!env.host.isMounted) return;
      final message = env.host.context.l10n.connPrivateKeyUnreadable;
      env.host.markNeedsBuild();
      runtime.isConnecting = false;
      runtime.connectionError = message;
      _showErrorSnackBar(message);
    } catch (e) {
      if (!env.host.isMounted) return;
      env.host.markNeedsBuild();
      runtime.isConnecting = false;
      runtime.connectionError = e.toString();
      _showErrorSnackBar(e.toString());
    }
  }

  /// herdr: セッション設定（移設元 `_setupHerdrSession` → herdr controller へ委譲）。
  ///
  /// 設計書 §3「herdr 固有は herdr へ」に従い、Env の herdr port へまとめて委譲
  /// する（setupSession）。戻り値は herdr controller が処理。
  Future<void> unselectedHerdrSetup(SshClient client) async {
    await env.herdr.setupSession(client);
  }

  // ---------------------------------------------------------------------------
  // 再接続成功（`_onReconnectSuccess`・移設元 L1200-1242・C2 委譲）
  // ---------------------------------------------------------------------------

  Future<void> onReconnectSuccess() async {
    if (!env.host.isMounted || env.host.isDisposed) return;

    env.input.resetTerminalMode();
    runtime.isPolling = false;
    runtime.recreatePaneReader?.call();

    if (runtime.backendKind == MultiplexerBackendKind.herdr) {
      final resolved = await env.herdr.reResolveAfterReconnect();
      if (resolved && !env.host.isDisposed) {
        runtime.pollingSuspended = false;
        runtime.startPolling();
      }
    } else {
      runtime.startPolling();
      runtime.startTreeRefresh?.call();
    }

    // C2: キューされた入力を送信（view-input へ委譲）
    await env.input.flushInputQueue();

    if (env.host.isMounted) env.host.markNeedsBuild();
  }

  // ---------------------------------------------------------------------------
  // 自動再接続（`_attemptReconnect`・移設元 L3107-3125）
  // ---------------------------------------------------------------------------

  Future<void> attemptReconnect() async {
    if (env.host.isDisposed) return;

    final sshNotifier = env.ref.read(sshProvider.notifier);
    await sshNotifier.reconnect();

    if (!env.host.isMounted || env.host.isDisposed) return;
    // 失敗時は次回ポーリングで再試行される（再試行上限は sshProvider 側）
  }

  // ---------------------------------------------------------------------------
  // 認証オプション（`_getAuthOptions`・移設元 L3126）
  // ---------------------------------------------------------------------------

  Future<SshConnectOptions> _getAuthOptions(dynamic connection) async {
    if (connection.authMethod == 'key' && connection.keyId != null) {
      final privateKey = await _secureStorage.getPrivateKey(connection.keyId!);
      if (privateKey == null) {
        throw SshAuthenticationError(
          'Private key is not readable. Please re-import the key.',
        );
      }
      final passphrase = await _secureStorage.getPassphrase(connection.keyId!);
      return SshConnectOptions(
        privateKey: privateKey,
        passphrase: passphrase,
        multiplexer: connection.multiplexer,
      );
    } else {
      final password = await _secureStorage.getPassword(connection.id);
      return SshConnectOptions(
        password: password,
        multiplexer: connection.multiplexer,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 切断（`_showDisconnectConfirmation` / `_disconnect`・移設元 L6867-7275）
  // ---------------------------------------------------------------------------

  Future<void> _restoreWindowPanePosition(dynamic sshNotifier) async {
    // ディープリンクまたは保存されたウィンドウ/ペイン位置を復元
    if (env.host.deepLinkWindowName != null) {
      final tmuxState = env.ref.read(tmuxProvider);
      final session = tmuxState.activeSession;
      if (session != null) {
        final targetName = env.host.deepLinkWindowName!;
        TmuxWindow? window;
        for (final w in session.windows) {
          if (w.name == targetName || w.name.endsWith(':$targetName')) {
            window = w;
            break;
          }
        }
        if (window != null) {
          env.ref.read(tmuxProvider.notifier).setActiveWindow(window.index);
          if (env.host.deepLinkPaneIndex != null &&
              env.host.deepLinkPaneIndex! < window.panes.length) {
            final pane = window.panes[env.host.deepLinkPaneIndex!];
            env.ref.read(tmuxProvider.notifier).setActivePane(pane.id);
          }
        }
      }
    } else if (env.host.lastWindowIndex != null) {
      final tmuxState = env.ref.read(tmuxProvider);
      final session = tmuxState.activeSession;
      if (session != null) {
        final window = session.windows.firstWhere(
          (w) => w.index == env.host.lastWindowIndex,
          orElse: () => session.windows.first,
        );
        env.ref.read(tmuxProvider.notifier).setActiveWindow(window.index);
        if (env.host.lastPaneId != null) {
          final pane = window.panes.firstWhere(
            (p) => p.id == env.host.lastPaneId,
            orElse: () => window.panes.first,
          );
          env.ref.read(tmuxProvider.notifier).setActivePane(pane.id);
        }
      }
    }
  }

  /// 切断確認ダイアログ（移設元 L6867-6916）。
  void showDisconnectConfirmation(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            context.l10n.termDisconnectTitle,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: Text(
            context.l10n.termDisconnectConfirm,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                context.l10n.termCancel,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await disconnect(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text(context.l10n.termClose),
            ),
          ],
        );
      },
    );
  }

  /// SSH接続を切断して前の画面に戻る（移設元 `_disconnect`）。
  Future<void> disconnect(BuildContext context) async {
    runtime.cancelPollTimers();

    // stale tmuxProvider 対策（T9）
    env.ref.read(tmuxProvider.notifier).clear();

    // 切断前にリサイズしたウィンドウを自動サイズへ戻す（G2）
    final restore = runtime.restoreResizedWindows;
    if (restore != null) {
      await restore();
    }

    await env.ref.read(sshProvider.notifier).disconnect();

    if (env.host.isMounted) {
      // ignore: use_build_context_synchronously
      Navigator.pop(context);
    }
  }

  /// エラー SnackBar（移設元 L3150・Retry=再 setup）。
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(env.host.context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: env.host.context.l10n.termRetry,
          textColor: Colors.white,
          // HEAD 同等: Retry は接続情報取得〜SSH 接続のフル再接続。
          onPressed: () {
            unawaited(connectAndSetup());
          },
        ),
      ),
    );
  }
}
