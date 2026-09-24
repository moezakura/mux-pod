// G1-G4: autoResize・復元・初回自動 fit・resize-window/resize-pane 実行
// （session-resize・移設元 L5774-6300 の tmux 部分。herdr resize は herdr 領域）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../providers/settings_provider.dart';
import '../../../../providers/ssh_provider.dart';
import '../../../../providers/terminal_display_provider.dart';
import '../../../../providers/tmux_provider.dart';
import '../../../../services/backend/domain/pane_writer.dart';
import '../../../../services/backend/domain/tmux_pane_writer.dart';
import '../../../../services/terminal/font_calculator.dart';
import '../../../../services/tmux/ssh_tmux_command_executor.dart';
import '../../../../services/tmux/tmux_models.dart';
import '../../../../widgets/dialogs/resize/pane_resize_dialog.dart';
import '../../../../widgets/dialogs/resize/resize_result.dart';
import '../../../../widgets/dialogs/resize/window_resize_dialog.dart';
import '../../../l10n/l10n_ext.dart';
import '../widgets/terminal_zoom.dart' show zoomedFontSize;
import 'session_env.dart';
import 'session_runtime.dart';

/// autoResize・window/pane リサイズの実行（`SessionRuntimeController` へ注入）。
class SessionResizeFlow {
  SessionResizeFlow(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  final Set<String> _resizedWindowTargets = <String>{};
  bool _windowsRestoredForBackground = false;
  Timer? _autoResizeDebounceTimer;
  Timer? _backgroundRestoreTimer;

  /// `_executeAutoResize`（G1・移設元 L5774-5840）。
  Future<void> executeAutoResize(
    Object paneObject, {
    bool force = false,
  }) async {
    final pane = paneObject as TmuxPane;
    if (runtime.isResizing) return;
    if (runtime.tmuxVersion != null &&
        !(runtime.tmuxVersion as dynamic).supportsResizeWindow) {
      return;
    }

    final displayState = env.ref.read(terminalDisplayProvider);
    final settings = env.ref.read(settingsProvider);

    final fontSize = zoomedFontSize(
      baseFontSize: settings.fontSize,
      zoomFactor: settings.zoomFactor,
      minFontSize: settings.minFontSize,
    );
    final targetCols = FontCalculator.calculateMaxCols(
      screenWidth: displayState.screenWidth,
      fontSize: fontSize,
      fontFamily: settings.fontFamily,
    );
    final targetRows = FontCalculator.calculateMaxRows(
      screenHeight: displayState.screenHeight,
      fontSize: fontSize,
      fontFamily: settings.fontFamily,
    );

    debugPrint(
      '[AutoResize] screenWidth=${displayState.screenWidth} '
      'screenHeight=${displayState.screenHeight} '
      'fontSize=$fontSize fontFamily=${settings.fontFamily} '
      'pane=${pane.id} current=${pane.width}x${pane.height} '
      'target=${targetCols}x$targetRows',
    );

    if (!force && pane.width == targetCols && pane.height == targetRows) {
      return;
    }

    runtime.isResizing = true;
    runtime.pollTimer?.cancel();
    try {
      final sshClient = env.ref.read(sshProvider.notifier).client;
      if (sshClient == null || !sshClient.isConnected) return;
      await env.tmux.resizeWindow(
        sshClient.tmuxExecutor,
        pane.id,
        cols: targetCols,
        rows: targetRows,
      );
      _resizedWindowTargets.add(pane.id);
      await env.tmux.setWindowRestoreTrap(
        sshClient.tmuxExecutor,
        _resizedWindowTargets.toList(),
      );
      await runtime.refreshSessionTree?.call();
      final updatedPane = env.ref.read(tmuxProvider).activePane;
      if (updatedPane != null) {
        env.ref.read(terminalDisplayProvider.notifier).updatePane(updatedPane);
      }
    } catch (e) {
      debugPrint('[AutoResize] Failed: $e');
    } finally {
      runtime.isResizing = false;
      if (env.host.isMounted && !env.host.isDisposed) {
        runtime.startPolling();
      }
    }
  }

  /// `_restoreResizedWindows`（G2・移設元 L5841-5853）。
  Future<void> restoreResizedWindows() async {
    if (_resizedWindowTargets.isEmpty) return;
    final targets = _resizedWindowTargets.toList();
    _resizedWindowTargets.clear();
    final client = env.ref.read(sshProvider.notifier).client;
    if (client == null || !client.isConnected) return;
    await env.tmux.restoreWindows(client.tmuxExecutor, targets);
  }

  /// `_scheduleInitialAutoResize`（G3・移設元 L5854-5868）。
  void scheduleInitialAutoResize([int attempt = 0]) {
    if (!env.host.isMounted || env.host.isDisposed) return;
    final screenWidth = env.ref.read(terminalDisplayProvider).screenWidth;
    final activePane = env.ref.read(tmuxProvider).activePane;
    if (activePane != null && screenWidth > 0) {
      executeAutoResize(activePane);
    } else if (attempt < 15) {
      Future.delayed(
        const Duration(milliseconds: 120),
        () => scheduleInitialAutoResize(attempt + 1),
      );
    }
  }

  /// `_handleResizePane`（tmux 絶対値 resize・移設元 L5869-5954）。
  Future<void> handleResizePane(Object paneObject) async {
    final pane = paneObject as TmuxPane;
    if (runtime.isResizing) return;

    if (!runtime.can(
      const PaneCapabilities(resize: true, absoluteResize: true),
    )) {
      return;
    }

    final displayState = env.ref.read(terminalDisplayProvider);
    final settings = env.ref.read(settingsProvider);
    final tmuxState = env.ref.read(tmuxProvider);

    final activeWindow = tmuxState.activeWindow;
    final allPanes = activeWindow?.panes ?? [pane];

    final result = await showDialog<ResizeResult>(
      context: env.host.context,
      builder: (context) => ResizePaneDialog(
        targetPane: pane,
        allPanesInWindow: allPanes,
        currentCols: pane.width,
        currentRows: pane.height,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
      ),
    );

    if (result == null || !env.host.isMounted) return;

    runtime.isResizing = true;
    runtime.pollTimer?.cancel();
    try {
      final writer = runtime.paneWriter;
      if (writer is! TmuxPaneWriter) return;
      await writer.resizePaneAbsolute(
        pane.id,
        cols: result.cols,
        rows: result.rows,
      );
      await runtime.refreshSessionTree?.call();
      final activePane = env.ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        env.ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      }
    } catch (e) {
      if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(env.host.context.l10n.termResizeFailed(e.toString())),
          ),
        );
      }
    } finally {
      runtime.isResizing = false;
      if (env.host.isMounted && !env.host.isDisposed) {
        runtime.startPolling();
      }
    }
  }

  /// `_handleResizeWindow`（G4・移設元 L6232-6300）。
  Future<void> handleResizeWindow(Object windowObject) async {
    final window = windowObject as TmuxWindow;
    if (runtime.isResizing) return;

    final displayState = env.ref.read(terminalDisplayProvider);
    final settings = env.ref.read(settingsProvider);

    final panes = window.panes;
    int windowCols = 80;
    int windowRows = 24;
    if (panes.isNotEmpty) {
      windowCols = panes
          .map((p) => p.left + p.width)
          .reduce((a, b) => a > b ? a : b);
      windowRows = panes
          .map((p) => p.top + p.height)
          .reduce((a, b) => a > b ? a : b);
    }

    final result = await showDialog<ResizeResult>(
      context: env.host.context,
      builder: (context) => ResizeWindowDialog(
        window: window,
        panes: panes,
        currentCols: windowCols,
        currentRows: windowRows,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
        supportsResizeWindow:
            (runtime.tmuxVersion as dynamic)?.supportsResizeWindow ?? false,
      ),
    );

    if (result == null || !env.host.isMounted) return;

    runtime.isResizing = true;
    runtime.pollTimer?.cancel();
    try {
      final sshClient = env.ref.read(sshProvider.notifier).client;
      if (sshClient == null) return;
      final tmuxState = env.ref.read(tmuxProvider);
      final target = '${tmuxState.activeSessionName}:${window.index}';
      await env.tmux.resizeWindow(
        sshClient.tmuxExecutor,
        target,
        cols: result.cols,
        rows: result.rows,
      );
      await runtime.refreshSessionTree?.call();
      final activePane = env.ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        env.ref.read(terminalDisplayProvider.notifier).updatePane(activePane);
      }
    } catch (e) {
      if (env.host.isMounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(env.host.context).showSnackBar(
          SnackBar(
            content: Text(env.host.context.l10n.termResizeFailed(e.toString())),
          ),
        );
      }
    } finally {
      runtime.isResizing = false;
      if (env.host.isMounted && !env.host.isDisposed) {
        runtime.startPolling();
      }
    }
  }

  /// P6: タイマー破棄（`cancelResizeTimers`）。
  void cancelResizeTimers() {
    _autoResizeDebounceTimer?.cancel();
    _autoResizeDebounceTimer = null;
    _backgroundRestoreTimer?.cancel();
    _backgroundRestoreTimer = null;
  }

  /// ライフサイクル: `didChangeMetrics` の debounce（P6 対象）。
  void onMetricsChanged() {
    final settings = env.ref.read(settingsProvider);
    if (!settings.isAutoResize) return;

    _autoResizeDebounceTimer?.cancel();
    _autoResizeDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!env.host.isMounted || env.host.isDisposed) return;
      final activePane = env.ref.read(tmuxProvider).activePane;
      if (activePane != null) {
        executeAutoResize(activePane);
      }
    });
  }

  /// ライフサイクル: バックグラウンド移行時の復元スケジュール（P6 対象）。
  void scheduleBackgroundRestore() {
    _backgroundRestoreTimer?.cancel();
    _backgroundRestoreTimer = Timer(const Duration(milliseconds: 600), () {
      if (env.host.isDisposed) return;
      if (_resizedWindowTargets.isNotEmpty) {
        _windowsRestoredForBackground = true;
      }
      restoreResizedWindows();
    });
  }

  /// ライフサイクル: バックグラウンド復帰時の force 再 fit。
  void onResumed() {
    _backgroundRestoreTimer?.cancel();
    if (_windowsRestoredForBackground) {
      _windowsRestoredForBackground = false;
      final pane = env.ref.read(tmuxProvider).activePane;
      if (pane != null && env.ref.read(settingsProvider).isAutoResize) {
        executeAutoResize(pane, force: true);
      }
    }
  }

  /// ライフサイクル: バックグラウンド確定/離脱時の即時復元。
  void onBackgroundNow() {
    if (_resizedWindowTargets.isNotEmpty) {
      _windowsRestoredForBackground = true;
    }
    restoreResizedWindows();
  }
}
