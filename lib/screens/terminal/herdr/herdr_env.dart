import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backend/domain/multiplexer_backend.dart';
import '../../../services/backend/domain/pane_writer.dart';
import '../../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../../services/herdr/herdr_pane_frame_reader.dart';
import '../../../services/tmux/commands/layout.dart';
import '../target_source.dart';
import 'herdr_types.dart';

class HerdrEnv {
  HerdrEnv({
    required this.ref,
    required this.contextProvider,
    required this.isMounted,
    required this.isDisposed,
    required this.backendKind,
    required this.can,
    required this.paneWriter,
    required this.sessionId,
    required this.workspaceLabel,
    required this.initialPaneId,
    required this.lastPaneId,
    required this.clock,
    required this.injectedCaretReader,
    required this.hasInjectedPaneContentReader,
    required this.clearTmuxProvider,
    required this.suspendPolling,
    required this.recreateReaders,
    required this.resetTerminalMode,
    required this.resetView,
    required this.boostPolling,
    required this.startPolling,
    required this.resumePolling,
    required this.attemptReconnect,
    required this.cancelPollTimer,
    required this.setFrameReader,
    required this.clearViewCaret,
    required this.onSplitPaneRequested,
    required this.sheetHost,
    required this.showLabelInputDialog,
    required this.isResizing,
    required this.setResizing,
    required this.setTargetSource,
  });

  final WidgetRef ref;

  final BuildContext Function() contextProvider;

  final bool Function() isMounted;

  final bool Function() isDisposed;

  final MultiplexerBackendKind Function() backendKind;

  final bool Function(PaneCapabilities required) can;

  final PaneWriter? Function() paneWriter;

  final String? Function() sessionId;

  final String? Function() workspaceLabel;

  final String? Function() initialPaneId;

  final String? Function() lastPaneId;

  final DateTime Function()? clock;

  /// テスト注入 caret reader（`TerminalScreen.herdrCaretReader`）。
  final HerdrCaretSnapshotReader? Function() injectedCaretReader;

  /// 診断用: 注入 paneContentReader があるか（HEAD の診断文字列と同一）。
  final bool Function() hasInjectedPaneContentReader;

  final VoidCallback clearTmuxProvider;

  final VoidCallback suspendPolling;

  final VoidCallback recreateReaders;

  final VoidCallback resetTerminalMode;

  final VoidCallback resetView;

  final VoidCallback boostPolling;

  final VoidCallback startPolling;

  final VoidCallback resumePolling;

  final VoidCallback attemptReconnect;

  final VoidCallback cancelPollTimer;

  final void Function(HerdrPaneFrameReader) setFrameReader;

  final VoidCallback clearViewCaret;

  final void Function(String paneId, SplitDirection direction)
  onSplitPaneRequested;

  final HerdrSheetHost? sheetHost;

  final Future<String?> Function(HerdrLabelDialogArgs args)
  showLabelInputDialog;

  final bool Function() isResizing;

  final void Function(bool value) setResizing;

  /// 表示対象 pane ソースを session（[TargetSource]）へ伝播する。
  /// poll は session 側の targetSource から現在 pane ID を読む。
  final void Function(TargetSource) setTargetSource;
}

/// herdr state の単一所有（notifier×2・リングバッファ・cache・bridge）と、
/// 切替・エポック照合・監視の窓口（合成ルート）。
///
/// dispose は arbitration §4 に従い 3 メソッドに分割する:
/// [disposeBridge]（P1・先頭単独）/ [disposeCaches]（P7）/ [disposeNotifiers]（P8）。
