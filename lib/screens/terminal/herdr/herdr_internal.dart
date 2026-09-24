import 'dart:async';

import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/tmux/commands/layout.dart';
import 'herdr_crud.dart';
import 'herdr_env.dart';
import 'herdr_resize.dart';
import 'herdr_types.dart';

/// セレクタから発火するダイアログ/操作の実装（resize・crud フローへ委譲）。
/// controller への依存を持たない（cycle 回避）。
class HerdrDialogActionsImpl implements HerdrDialogActions {
  HerdrDialogActionsImpl(this.resize, this.crud, this.env);

  final HerdrResizeFlow resize;
  final HerdrCrudFlow crud;
  final HerdrEnv env;

  @override
  void showResizePaneChooser(
    List<MultiplexerSession> sessions,
    MultiplexerWindow window,
  ) => resize.showResizePaneChooser(sessions, window);

  @override
  void showResizeTerminal() {
    unawaited(resize.handleResizeTerminal());
  }

  @override
  void showCreateTabDialog(MultiplexerSession workspace) =>
      crud.showCreateTabDialog(workspace);

  @override
  void showRenameTabDialog(
    MultiplexerSession workspace,
    MultiplexerWindow tab,
  ) => crud.showRenameTabDialog(workspace, tab);

  @override
  void confirmCloseTab({
    required MultiplexerSession workspace,
    required MultiplexerWindow tab,
    required bool isLastTab,
  }) => crud.confirmAndCloseTab(
    workspace: workspace,
    tab: tab,
    isLastTab: isLastTab,
  );

  @override
  void confirmKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastTab,
  }) => crud.confirmAndKillPane(
    paneId: paneId,
    paneTitle: paneTitle,
    isLastPane: isLastPane,
    isLastTab: isLastTab,
  );

  @override
  void splitPane(String paneId, SplitDirection direction) {
    env.onSplitPaneRequested(paneId, direction);
  }
}
