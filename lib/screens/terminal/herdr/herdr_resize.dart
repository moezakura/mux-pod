import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/terminal_display_provider.dart';
import '../../../services/backend/domain/multiplexer_pane.dart';
import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/backend/domain/pane_writer.dart';
import '../../../services/herdr/herdr_resize_math.dart';
import '../../../widgets/dialogs/pane_chooser_dialog.dart';
import '../../../widgets/dialogs/resize_dialog.dart';
import 'herdr_messages.dart';
import 'herdr_navigation.dart';
import 'herdr_sync.dart';
import 'herdr_types.dart';

/// herdr の resize（C4: pane 選択モーダル・絶対値→相対換算・ターミナル全体）。
class HerdrResizeFlow {
  HerdrResizeFlow(this._host, this._sync);

  final HerdrHost _host;
  final HerdrSyncFlow _sync;

  /// リサイズ対象 pane 選択モーダル（条件2/3/10/11・ユーザー決定①〜③）。
  void showResizePaneChooser(
    List<MultiplexerSession> sessions,
    MultiplexerWindow window,
  ) {
    if (window.panes.isEmpty) {
      _host.recordSwitchEvent('resize stale abort: empty pane list');
      return;
    }
    _host.recordSwitchEvent('resize chooser shown');

    showDialog(
      context: _host.context,
      builder: (dialogContext) {
        return PaneChooserDialog(
          panes: window.panes,
          initialPaneId: _host.paneId,
          labelBuilder: (pane) => herdrPaneLabel(pane, _host.context.l10n),
          onResize: (paneId) {
            Navigator.pop(dialogContext);
            final pane = _sync.findPane(sessions, paneId);
            if (pane == null) {
              _host.recordSwitchEvent(
                'resize stale abort: pane not found ($paneId)',
              );
              return;
            }
            handleResizePane(pane, panes: window.panes);
          },
        );
      },
    );
  }

  /// herdr ペインを絶対値（Cols/Rows）でリサイズする（絶対値→相対換算）。
  Future<void> handleResizePane(
    MultiplexerPane pane, {
    List<MultiplexerPane> panes = const [],
  }) async {
    if (_host.isResizing) return;
    if (!_host.can(const PaneCapabilities(resize: true))) return;

    final displayState = _host.ref.read(terminalDisplayProvider);
    final settings = _host.ref.read(settingsProvider);

    final result = await showDialog<ResizeResult>(
      context: _host.context,
      builder: (context) => HerdrResizePaneDialog(
        targetPaneId: pane.id,
        panes: panes,
        currentCols: pane.width,
        currentRows: pane.height,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
      ),
    );
    if (result == null || !_host.isMounted) return;

    _host.setResizing(true);
    _host.cancelPollTimer();
    try {
      final writer = _host.paneWriter;
      if (writer == null) return;

      await _resizeOneAxis(
        writer,
        pane: pane,
        panes: panes,
        horizontal: true,
        targetCells: result.cols,
      );
      await _resizeOneAxis(
        writer,
        pane: pane,
        panes: panes,
        horizontal: false,
        targetCells: result.rows,
      );

      await _host.syncAfterMutation(eventLabel: 'resize sync');
      _host.recordSwitchEvent(
        'resize executed: pane=${pane.id} cols=${result.cols} '
        'rows=${result.rows}',
      );
    } on PaneOperationNoopException catch (e) {
      // ignore: use_build_context_synchronously
      herdrShowNoop(_host.context, e);
      _host.recordSwitchEvent('resize no-op (reason: ${e.reason ?? '<null>'})');
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'resize');
    } finally {
      _host.setResizing(false);
      if (_host.isMounted && !_host.isDisposed) _host.startPolling();
    }
  }

  /// ターミナル全体 resize（Select Session の Resize 導線・ユーザー指示）。
  Future<void> handleResizeTerminal() async {
    if (_host.isResizing) return;

    final bridge = _host.resizeBridge;
    if (bridge == null) {
      if (_host.isMounted && !_host.isDisposed) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(_host.context).showSnackBar(
          SnackBar(content: Text(_host.context.l10n.termSshNotAvailable)),
        );
      }
      return;
    }

    final displayState = _host.ref.read(terminalDisplayProvider);
    final settings = _host.ref.read(settingsProvider);

    final current = await bridge.currentPtySize();
    if (!_host.isMounted || _host.isDisposed) return;

    final result = await showDialog<ResizeResult>(
      // ignore: use_build_context_synchronously
      context: _host.context,
      builder: (context) => HerdrResizeTerminalDialog(
        currentCols: current.cols,
        currentRows: current.rows,
        screenWidth: displayState.screenWidth,
        screenHeight: displayState.screenHeight,
        fontSize: displayState.calculatedFontSize,
        fontFamily: settings.fontFamily,
      ),
    );
    if (result == null || !_host.isMounted) return;

    _host.setResizing(true);
    _host.cancelPollTimer();
    try {
      final ok = await bridge.resize(result.cols, result.rows);
      if (!ok) {
        if (_host.isMounted && !_host.isDisposed) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(_host.context).showSnackBar(
            SnackBar(content: Text(_host.context.l10n.termResizeFailedHerdr)),
          );
        }
        return;
      }
      if (!_host.isMounted || _host.isDisposed) return;
      await _host.syncAfterMutation(eventLabel: 'resize terminal sync');
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'resize terminal');
    } finally {
      _host.setResizing(false);
      if (_host.isMounted && !_host.isDisposed) _host.startPolling();
    }
  }

  /// コンテナ（ウィンドウ）のセル数を panes の rect から計算する。
  int _containerCells(List<MultiplexerPane> panes, {required bool horizontal}) {
    if (panes.isEmpty) return 0;
    var min = horizontal ? panes.first.left : panes.first.top;
    var max = 0;
    for (final p in panes) {
      final pos = horizontal ? p.left : p.top;
      final end = pos + (horizontal ? p.width : p.height);
      if (pos < min) min = pos;
      if (end > max) max = end;
    }
    return max - min;
  }

  /// 1 軸（横 = Cols / 縦 = Rows）の絶対値変更を相対量へ換算して送信する。
  Future<void> _resizeOneAxis(
    PaneWriter writer, {
    required MultiplexerPane pane,
    required List<MultiplexerPane> panes,
    required bool horizontal,
    required int targetCells,
  }) async {
    final container = _containerCells(panes, horizontal: horizontal);
    final current = horizontal ? pane.width : pane.height;
    final delta = PaneResizeMath.absoluteToDelta(
      currentCells: current,
      targetCells: targetCells,
      containerCells: container,
    );
    if (delta == null || delta == 0) return;

    if (delta > 0) {
      final direction = PaneResizeMath.resolveDirection(
        target: pane,
        panes: panes,
        horizontal: horizontal,
        grow: true,
      );
      if (direction == null) return;
      await writer.resizePane(pane.id, direction, delta);
    } else {
      final side = PaneResizeMath.resolveDirection(
        target: pane,
        panes: panes,
        horizontal: horizontal,
        grow: false,
      );
      if (side == null) return;
      final neighbor = _adjacentPane(panes, pane.id, side);
      if (neighbor == null) return;
      await writer.resizePane(
        neighbor.id,
        herdrOppositeDirection(side),
        delta.abs(),
      );
    }
  }

  /// [direction] の位置に隣接する pane を rect の重なりから特定して返す。
  MultiplexerPane? _adjacentPane(
    List<MultiplexerPane> panes,
    String paneId,
    String direction,
  ) {
    MultiplexerPane? target;
    for (final p in panes) {
      if (p.id == paneId) {
        target = p;
        break;
      }
    }
    if (target == null || target.width <= 0 || target.height <= 0) return null;

    final right = target.left + target.width;
    final bottom = target.top + target.height;
    for (final p in panes) {
      if (p.id == paneId) continue;
      if (p.width <= 0 || p.height <= 0) continue;
      final overlapsVertically =
          p.top < bottom && p.top + p.height > target.top;
      final overlapsHorizontally =
          p.left < right && p.left + p.width > target.left;
      switch (direction) {
        case 'right':
          if (p.left >= right && overlapsVertically) return p;
        case 'left':
          if (p.left + p.width <= target.left && overlapsVertically) return p;
        case 'down':
          if (p.top >= bottom && overlapsHorizontally) return p;
        case 'up':
          if (p.top + p.height <= target.top && overlapsHorizontally) return p;
      }
    }
    return null;
  }
}
