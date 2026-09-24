// P4: root State が合成アダプタへ提供する [TerminalScreenAccess] の実装。
//
// root State（terminal_screen.dart）からアクセサ群を切り出し、root を
// 500 行未満に保つ。値は widget / framework / GlobalKey からのみ取得し、
// 状態は持たない（#125 の切断UX は [TerminalReconnectPanel] へ委譲）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backend/domain/pane_content_reader.dart';
import '../../services/herdr/caret/herdr_caret_snapshot_reader.dart';
import '../../widgets/scroll_to_bottom_button.dart'
    show ScrollToBottomButtonState;
import 'terminal_reconnect_panel.dart';
import 'terminal_screen.dart' show TerminalScreen;
import 'terminal_screen_access.dart';
import 'widgets/ansi_text_view.dart' show AnsiTextViewState;

class TerminalScreenAccessImpl implements TerminalScreenAccess {
  TerminalScreenAccessImpl({
    required this.ref,
    required TerminalScreen screen,
    required BuildContext Function() contextOf,
    required bool Function() isMountedFn,
    required bool Function() isDisposedFn,
    required void Function() markNeedsBuildFn,
    required this.ansiTextViewKey,
    required this.scrollToBottomKey,
    required this.reconnectUi,
  }) : _screen = screen,
       _contextOf = contextOf,
       _isMounted = isMountedFn,
       _isDisposed = isDisposedFn,
       _markNeedsBuild = markNeedsBuildFn;

  @override
  final WidgetRef ref;

  final TerminalScreen _screen;
  final BuildContext Function() _contextOf;
  final bool Function() _isMounted;
  final bool Function() _isDisposed;
  final void Function() _markNeedsBuild;

  @override
  final GlobalKey<AnsiTextViewState> ansiTextViewKey;

  @override
  final GlobalKey<ScrollToBottomButtonState> scrollToBottomKey;

  /// #125 切断UX の状態所有者（root が生成・破棄する）。
  final TerminalReconnectPanel reconnectUi;

  @override
  bool get isMounted => _isMounted();

  @override
  bool get isDisposed => _isDisposed();

  @override
  void markNeedsBuild() => _markNeedsBuild();

  @override
  BuildContext get context => _contextOf();

  @override
  String get connectionId => _screen.connectionId;

  @override
  String? get sessionName => _screen.sessionName;

  @override
  String? get sessionId => _screen.sessionId;

  @override
  int? get lastWindowIndex => _screen.lastWindowIndex;

  @override
  String? get lastPaneId => _screen.lastPaneId;

  @override
  String? get deepLinkWindowName => _screen.deepLinkWindowName;

  @override
  int? get deepLinkPaneIndex => _screen.deepLinkPaneIndex;

  @override
  String? get initialPaneId => _screen.initialPaneId;

  @override
  PaneContentReader? get injectedPaneContentReader => _screen.paneContentReader;

  @override
  DateTime Function()? get herdrCacheClock => _screen.herdrCacheClock;

  @override
  HerdrCaretSnapshotReader? get herdrCaretReader => _screen.herdrCaretReader;

  // ---- #125 切断UX（状態所有者へ委譲）----

  @override
  void showCommErrorPanel({
    required String title,
    required String body,
    required String detail,
    required Future<void> Function() onRetry,
  }) => reconnectUi.show(
    title: title,
    body: body,
    detail: detail,
    onRetry: onRetry,
  );

  @override
  void closeCommErrorPanel() => reconnectUi.close();

  @override
  void onConnectionRestored() => reconnectUi.onConnectionRestored();

  @override
  void syncReconnectCountdown({
    required bool isReconnecting,
    required bool isWaitingForNetwork,
    DateTime? nextRetryAt,
  }) => reconnectUi.sync(
    isReconnecting: isReconnecting,
    isWaitingForNetwork: isWaitingForNetwork,
    nextRetryAt: nextRetryAt,
  );
}
