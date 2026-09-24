// poll 本体・表示更新駆動（session-poll・移設元 L2197-2413 / L2953-3110 の
// content 差分 / geometry / latency 部分）。
import 'dart:async';

import '../../../../providers/ssh_provider.dart';
import '../../../../providers/tmux_provider.dart';
import '../../../../providers/terminal_display_provider.dart';
import '../../../../services/backend/domain/multiplexer_backend.dart'
    show MultiplexerBackendKind;
import '../../../../services/backend/domain/pane_frame_reader.dart';
import '../../../../services/backend/domain/pane_read.dart';
import 'session_connection.dart';
import 'session_env.dart';
import 'session_models.dart';
import 'session_runtime.dart';

/// poll ループの本体（`SessionRuntimeController.pollTick` に注入される）。
class SessionPollEngine {
  SessionPollEngine(
    this.env,
    this.runtime, {
    required SessionConnectionFlow connection,
  }) : _connection = connection;

  final SessionEnv env;
  final SessionRuntimeController runtime;
  final SessionConnectionFlow _connection;

  /// `_pollPaneContent` の移設（C1/C7 は port 呼出）。
  Future<void> pollPaneContent() async {
    if (runtime.isPolling || env.host.isDisposed) return;
    runtime.isPolling = true;

    try {
      final sshNotifier = env.ref.read(sshProvider.notifier);
      final sshClient = sshNotifier.client;

      if (sshClient == null || !sshClient.isConnected) {
        final currentState = env.ref.read(sshProvider);
        if (!currentState.isReconnecting) {
          await _connection.attemptReconnect();
        }
        runtime.isPolling = false;
        return;
      }

      final paneId = runtime.targetSource?.currentPaneId;
      final reader = runtime.paneReader;
      final frameReader = runtime.frameReader;
      if (paneId == null || reader == null) {
        runtime.isPolling = false;
        return;
      }

      // A3改: read 開始前に対象同一性を記録。
      final herdrIdentity = env.herdr.captureTargetIdentity();

      final startTime = DateTime.now();

      final snapshot = frameReader != null
          ? (await frameReader.read(
              PaneFrameRequest(PaneReadRequest.live(paneId: paneId)),
            )).toSnapshot()
          : await reader.readPane(PaneReadRequest.live(paneId: paneId));

      final endTime = DateTime.now();

      if (!env.host.isMounted || env.host.isDisposed) return;

      if (!env.herdr.isCurrentTargetIdentity(herdrIdentity)) return;

      // ポーリング契機の pane indicator 再設定（🤝#3）
      await env.herdr.refreshPaneIndicatorFromCache();

      // カーソル位置とペインサイズを更新
      final geometry = snapshot.geometry;
      final w = geometry?.width ?? 0;
      final h = geometry?.height ?? 0;
      if (w > 0 && h > 0) {
        if (w != runtime.viewNotifier.value.paneWidth ||
            h != runtime.viewNotifier.value.paneHeight) {
          runtime.viewNotifier.value = runtime.viewNotifier.value.copyWith(
            paneWidth: w,
            paneHeight: h,
          );
          final currentActivePane = env.ref.read(tmuxProvider).activePane;
          if (currentActivePane != null) {
            env.ref
                .read(terminalDisplayProvider.notifier)
                .updatePane(currentActivePane.copyWith(width: w, height: h));
          }
        }

        final activePaneId = env.ref.read(tmuxProvider).activePaneId;
        if (activePaneId != null) {
          env.ref
              .read(tmuxProvider.notifier)
              .updateCursorPosition(
                activePaneId,
                snapshot.cursorX,
                snapshot.cursorY,
              );
        }
      }

      final processedOutput = snapshot.content;
      final paneModeOutput = snapshot.paneMode;

      // G7: latency（専用 notifier・唯一の書込）
      final latency = endTime.difference(startTime).inMilliseconds;
      if (env.host.isMounted && !env.host.isDisposed) {
        runtime.latencyNotifier.value = latency;
      }

      // 適応型ポーリング記録
      if (processedOutput == runtime.lastPolledContent) {
        runtime.unchangedPolls++;
      } else {
        runtime.unchangedPolls = 0;
        runtime.lastPolledContent = processedOutput;
      }

      // コンテンツ差分があれば更新（C1/C7 port 経由・select バッファは 3 段契約）
      final currentView = runtime.viewNotifier.value;
      if (processedOutput != currentView.content ||
          !caretEquals(snapshot.caret, currentView.caret)) {
        if (env.input.isSelectManualActive) {
          env.input.captureSelectUpdate(
            content: processedOutput,
            caret: snapshot.caret,
            targetIdentity: herdrIdentity,
          );
        } else {
          runtime.scheduleUpdate(
            processedOutput,
            targetIdentity: herdrIdentity,
            caret: snapshot.caret,
          );
        }
      }

      // tmux copy-mode 検出による自動モード切替（view-input port）
      if (env.host.isMounted && !env.host.isDisposed) {
        final paneMode = paneModeOutput.trim();
        final isTmuxCopyMode = paneMode.isNotEmpty;
        env.input.observePaneMode(paneMode);
        if (isTmuxCopyMode && env.input.isScrollModeSourceNone) {
          env.input.handleTmuxCopyModeDetected();
        } else if (!isTmuxCopyMode && env.input.isCopyModeActive) {
          env.input.handleTmuxCopyModeEnded();
          runtime.applyBufferedUpdate();
        }
      }

      runtime.updatePollingInterval(
        copyModeActive:
            env.input.isCopyModeActive || env.input.isScrollSendActive,
      );
    } catch (e) {
      // A2: herdr は例外種別で分岐。tmux パスは従来挙動。
      if (runtime.backendKind == MultiplexerBackendKind.herdr) {
        await env.herdr.handlePollError(e);
      } else {
        if (!env.host.isDisposed) {
          final currentState = env.ref.read(sshProvider);
          if (!currentState.isReconnecting) {
            await _connection.attemptReconnect();
          }
        }
      }
    } finally {
      runtime.isPolling = false;
    }
  }
}
