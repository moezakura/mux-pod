import 'package:flutter/material.dart';

import '../../providers/tmux_provider.dart';
import '../../services/backend/domain/multiplexer_pane.dart';
import '../../services/backend/domain/multiplexer_window.dart';
import '../../services/tmux/commands/layout.dart';
import '../../services/tmux/tmux_to_domain.dart';
import '../../services/tmux/tmux_models.dart';
import '../../widgets/dialogs/pane_chooser_dialog.dart';
import '../../widgets/multiplexer_tiles.dart';
import '../../l10n/l10n_ext.dart';
import 'pane_layout_painter.dart';
import 'pane_layout_visualizer.dart';
import 'resize_window_chooser_dialog.dart';
import 'selector_sheet.dart';
import 'tmux_pane_label.dart';

/// セレクタ起動が session 側へ委譲する mutation アクションの束。
///
/// tmux のセレクタ（Session / Window / Pane）とリサイズ・分割の起動に必要な
/// コールバックと能力フラグを束ねる。herdr 側は herdr のセレクタ起動が
/// このファイルの [showMultiplexerSheet] / [closeSelectorThen] のみを利用し、
/// このクラスの tmux 特化メンバは使わない。
class SelectorLaunchActions {
  /// 現在位置（H-1）を担う [SelectorContext]。
  final SelectorContext? Function() contextOf;

  /// セッション選択完了（即閉じ後に実行）。
  final void Function(String sessionName) onSelectSession;

  /// ウィンドウ選択完了（即閉じ後に実行）。
  final void Function(String sessionName, int windowIndex) onSelectWindow;

  /// ペイン選択完了（即閉じ後に実行）。
  final void Function(String paneId) onSelectPane;

  /// 分割リクエスト（Visualizer / タイルからの split）。
  final void Function(String paneId, SplitDirection direction) onSplitPane;

  /// ペインリサイズ（`PaneChooserDialog` の選択済み pane）。
  final void Function(TmuxPane pane) onResizePane;

  /// ウィンドウリサイズ（`ResizeWindowChooserDialog` の選択済み window）。
  final void Function(TmuxWindow window) onResizeWindow;

  /// ウィンドウを閉じる確認（`onClose` 経由）。
  final void Function({
    required String sessionName,
    required int windowIndex,
    required String windowName,
    required bool isLastWindow,
  })
  onConfirmKillWindow;

  /// ペインを閉じる確認（`onClose` / 長押し経由）。
  final void Function({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastWindow,
  })
  onConfirmKillPane;

  /// ウィンドウ名変更ダイアログ（`onRename` 経由）。
  final void Function(TmuxSession session, TmuxWindow window) onRenameWindow;

  /// 新規ウィンドウ作成（`onCreateWindow`・headerAction 経由）。
  final void Function(TmuxSession session) onCreateWindow;

  // 能力（T4: `_can` の分解）。
  final bool canTabCrud;
  final bool canResize;
  final bool canRename;
  final bool canClose;
  final bool canSplitPane;

  /// ルート State 生存確認（`mounted && !_isDisposed`）。
  final bool Function() isSafe;

  /// シート/ダイアログが閉じた後の後始末（`_scrollToBottomKey.show` 等）。
  final VoidCallback onSheetClosed;

  const SelectorLaunchActions({
    required this.contextOf,
    required this.onSelectSession,
    required this.onSelectWindow,
    required this.onSelectPane,
    required this.onSplitPane,
    required this.onResizePane,
    required this.onResizeWindow,
    required this.onConfirmKillWindow,
    required this.onConfirmKillPane,
    required this.onRenameWindow,
    required this.onCreateWindow,
    required this.canTabCrud,
    required this.canResize,
    required this.canRename,
    required this.canClose,
    required this.canSplitPane,
    required this.isSafe,
    required this.onSheetClosed,
  });
}

/// 共通 1 段セレクタシート（[MultiplexerSelectorSheet]）を開く汎用ヘルパー。
///
/// 呼び出し側が構築した [children]（タイル。onTap は「pop → コールバック」）と
/// [headerActions]（mutation ボタン）を単一階層のシートとして表示する。
/// [top] は一覧の上部に表示するウィジェット。シートが閉じた後は
/// [onSheetClosed] を呼ぶ（既存 3 段セレクタと同じライフサイクル）。
///
/// [asyncContent] を指定すると、**シートを即時 open して loading を表示**し、
/// 非同期で取得完了後に一覧を表示する（バグ3 根本対応）。[retry] を指定すると、
/// 取得失敗時に Retry ボタンを表示する。
Future<void> showMultiplexerSheet({
  required BuildContext context,
  required String title,
  required IconData icon,
  Widget? top,
  bool topExpected = false,
  List<Widget> children = const [],
  List<Widget> headerActions = const [],
  Future<SelectorContent> Function()? asyncContent,
  VoidCallback? retry,
  VoidCallback? onSheetClosed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: MultiplexerSelectorSheet(
          title: title,
          icon: icon,
          top: top,
          topExpected: topExpected,
          headerActions: headerActions,
          asyncContent: asyncContent,
          retry: retry,
          children: children,
        ),
      );
    },
  ).then((_) => onSheetClosed?.call());
}

/// セレクタシートを閉じてから mutation アクションを起動する。
///
/// 既存セレクタの「pop → 200ms 待ち → コールバック」順を維持する（ダイアログ
/// 表示前にシートの dismiss アニメーションを開始させる）。待機後にルート State
/// が生存している場合のみ [action] を実行する。
void closeSelectorThen(
  BuildContext context,
  bool Function() isSafe,
  VoidCallback action,
) {
  Navigator.pop(context);
  Future<void>.delayed(const Duration(milliseconds: 200), () {
    if (isSafe()) action();
  });
}

/// tmux 経路の薄いアダプタ: [TmuxState] のアクティブウィンドウを共通 domain の
/// [MultiplexerPane] 一覧へ変換し、共通シェルへ渡す。
///
/// アクティブウィンドウが null の場合は空リストを渡す（LOW-1: シェルの
/// ペイン数ガードで非表示に倒れる）。タップは tmux 用セレクタへ。
Widget buildTmuxPaneIndicator(
  SelectorLaunchActions actions,
  TmuxState tmuxState, {
  required VoidCallback onTap,
}) {
  final window = tmuxState.activeWindow;
  final panes = window?.toDomain().panes ?? const <MultiplexerPane>[];
  return PaneIndicatorShell(
    panes: panes,
    activePaneId: tmuxState.activePaneId,
    onTap: onTap,
  );
}

/// tmux のペインレイアウトビジュアライザを構築する（T2 / Q3・domain ベース）。
///
/// 共通 domain の [MultiplexerWindow]（geometry 込み）から
/// [PaneLayoutVisualizer] を返す。[activePaneId] は呼び出し側が明示的に渡す。
/// 分割不可（[actions.canSplitPane] == false）では split を無効化し選択のみ
/// 許可する（H-4）。
Widget? buildPaneLayoutVisualizer(
  MultiplexerWindow window,
  String? activePaneId,
  void Function(String paneId) onPaneSelected,
  void Function(String paneId, SplitDirection direction)? onSplitRequested,
) {
  return PaneLayoutVisualizer(
    panes: window.panes,
    activePaneId: activePaneId,
    onPaneSelected: onPaneSelected,
    onSplitRequested: onSplitRequested,
  );
}

/// セッション選択シートを表示（選択即閉じ・元 tmux 挙動）。
///
/// タップした session は [SelectorLaunchActions.onSelectSession] で即時確定して
/// シートを閉じる。
void showSessionSelectorTap(
  BuildContext context,
  SelectorLaunchActions actions,
  TmuxState tmuxState,
) {
  final sessions = tmuxState.sessions.map((s) => s.toDomain()).toList();
  final current = actions.contextOf();
  showMultiplexerSheet(
    context: context,
    title: context.l10n.termSelectSession,
    icon: Icons.folder,
    onSheetClosed: actions.onSheetClosed,
    children: [
      for (final session in sessions)
        MultiplexerSessionTile(
          key: ValueKey('mux-sel-session-${session.name}'),
          session: session,
          isActive: isCurrentSession(session, current),
          onTap: () {
            Navigator.pop(context);
            actions.onSelectSession(session.name);
          },
        ),
    ],
  );
}

/// ウィンドウ選択シートを表示（選択即閉じ・元 tmux 挙動）。
///
/// 現在のアクティブ session の window 一覧を 1 階層で表示する。タップした
/// window は [SelectorLaunchActions.onSelectWindow] で即時確定してシートを
/// 閉じる。mutation（New Window / Resize / Rename / Close）は能力あり（接続中）
/// 時のみヘッダーとタイルに表示する（H-4）。
void showWindowSelectorTap(
  BuildContext context,
  SelectorLaunchActions actions,
  TmuxState tmuxState, {
  required VoidCallback showResizeWindowChooser,
}) {
  final session = tmuxState.activeSession;
  if (session == null) return;
  final domainSession = session.toDomain();
  final current = actions.contextOf();
  final primary = Theme.of(context).colorScheme.primary;
  showMultiplexerSheet(
    context: context,
    title: context.l10n.termSelectWindow,
    icon: Icons.tab,
    onSheetClosed: actions.onSheetClosed,
    headerActions: [
      if (actions.canResize)
        IconButton(
          icon: Icon(Icons.open_in_full, color: primary),
          tooltip: context.l10n.termResizeWindow,
          onPressed: () => closeSelectorThen(
            context,
            actions.isSafe,
            showResizeWindowChooser,
          ),
        ),
      if (actions.canTabCrud)
        IconButton(
          icon: Icon(Icons.add, color: primary),
          tooltip: context.l10n.termNewWindow,
          onPressed: () => closeSelectorThen(
            context,
            actions.isSafe,
            () => actions.onCreateWindow(session),
          ),
        ),
    ],
    children: [
      for (final window in domainSession.windows)
        MultiplexerWindowTile(
          key: ValueKey('mux-sel-window-${window.id ?? window.index}'),
          window: window,
          isActive: isCurrentWindow(window, current),
          onTap: () {
            Navigator.pop(context);
            actions.onSelectWindow(session.name, window.index);
          },
          onRename: actions.canRename
              ? () => closeSelectorThen(context, actions.isSafe, () {
                  final tmuxWindow = tmuxWindowOf(session, window);
                  if (tmuxWindow != null) {
                    // inventory: TERM-CRUD-009
                    actions.onRenameWindow(session, tmuxWindow);
                  }
                })
              : null,
          onResize: actions.canResize
              ? () => closeSelectorThen(
                  context,
                  actions.isSafe,
                  showResizeWindowChooser,
                )
              : null,
          onClose: actions.canClose
              ? () => closeSelectorThen(context, actions.isSafe, () {
                  // inventory: TERM-CRUD-007
                  actions.onConfirmKillWindow(
                    sessionName: session.name,
                    windowIndex: window.index,
                    windowName: window.name,
                    isLastWindow: session.windows.length == 1,
                  );
                })
              : null,
        ),
    ],
  );
}

/// ペイン選択シートを表示（選択即閉じ・元 tmux 挙動）。
///
/// 現在のアクティブ window の pane 一覧を 1 階層で表示する。タップした pane は
/// [SelectorLaunchActions.onSelectPane] で即時確定してシートを閉じる。
/// ペインのグラフィカルなレイアウト（[PaneLayoutVisualizer]）を一覧の上部に
/// 表示し、分割は [SelectorLaunchActions.onSplitPane]、リサイズは
/// [showResizePaneChooser] に到達する（T2）。
void showPaneSelectorTap(
  BuildContext context,
  SelectorLaunchActions actions,
  TmuxState tmuxState, {
  required VoidCallback showResizePaneChooser,
}) {
  final session = tmuxState.activeSession;
  final window = tmuxState.activeWindow;
  if (session == null || window == null) return;
  final domainWindow = window.toDomain();
  final current = actions.contextOf();
  final primary = Theme.of(context).colorScheme.primary;
  showMultiplexerSheet(
    context: context,
    title: context.l10n.termSelectPane,
    icon: Icons.terminal,
    onSheetClosed: actions.onSheetClosed,
    top: buildPaneLayoutVisualizer(
      domainWindow,
      tmuxState.activePaneId,
      (paneId) {
        Navigator.pop(context);
        actions.onSelectPane(paneId);
      },
      actions.canSplitPane
          ? (paneId, direction) {
              Navigator.pop(context);
              actions.onSplitPane(paneId, direction);
            }
          : null,
    ),
    headerActions: [
      if (actions.canResize)
        IconButton(
          icon: Icon(Icons.open_in_full, color: primary),
          tooltip: context.l10n.termResizePane,
          onPressed: () =>
              closeSelectorThen(context, actions.isSafe, showResizePaneChooser),
        ),
    ],
    children: [
      for (final pane in domainWindow.panes)
        MultiplexerPaneTile(
          key: ValueKey('mux-sel-pane-${pane.id}'),
          pane: pane,
          paneTitle: tmuxPaneLabelFor(tmuxState, pane.id, context.l10n),
          subtitle: tmuxPaneSubtitleFor(tmuxState, pane),
          isActive: isCurrentPane(pane, current),
          onTap: () {
            Navigator.pop(context);
            actions.onSelectPane(pane.id);
          },
          onLongPress: actions.canClose
              ? () => closeSelectorThen(context, actions.isSafe, () {
                  // inventory: TERM-CRUD-004
                  actions.onConfirmKillPane(
                    paneId: pane.id,
                    paneTitle: tmuxPaneLabelFor(
                      tmuxState,
                      pane.id,
                      context.l10n,
                    ),
                    isLastPane: window.panes.length == 1,
                    isLastWindow: session.windows.length == 1,
                  );
                })
              : null,
          onResize: actions.canResize
              ? () => closeSelectorThen(
                  context,
                  actions.isSafe,
                  showResizePaneChooser,
                )
              : null,
          onClose: actions.canClose
              ? () => closeSelectorThen(context, actions.isSafe, () {
                  // inventory: TERM-CRUD-004
                  actions.onConfirmKillPane(
                    paneId: pane.id,
                    paneTitle: tmuxPaneLabelFor(
                      tmuxState,
                      pane.id,
                      context.l10n,
                    ),
                    isLastPane: window.panes.length == 1,
                    isLastWindow: session.windows.length == 1,
                  );
                })
              : null,
        ),
    ],
  );
}

/// tmux のリサイズ対象 pane 選択モーダル（PaneChooserDialog・共通 domain ベース）。
void showResizePaneChooserTap(
  BuildContext context,
  SelectorLaunchActions actions,
  TmuxState tmuxState,
) {
  final window = tmuxState.activeWindow;
  if (window == null || window.panes.isEmpty) return;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return PaneChooserDialog(
        panes: window.panes.map((p) => p.toDomain()).toList(),
        initialPaneId: tmuxState.activePaneId,
        onResize: (paneId) {
          Navigator.pop(dialogContext);
          // inventory: TERM-RESIZE-004
          final pane = window.panes.where((p) => p.id == paneId).firstOrNull;
          if (pane != null) actions.onResizePane(pane);
        },
      );
    },
  ).then((_) => actions.onSheetClosed());
}

/// リサイズ対象のウィンドウをグラフィカルに選択するダイアログ。
void showResizeWindowChooserTap(
  BuildContext context,
  SelectorLaunchActions actions,
  TmuxState tmuxState,
) {
  final session = tmuxState.activeSession;
  if (session == null || session.windows.isEmpty) return;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return ResizeWindowChooserDialog(
        windows: session.windows,
        activeWindowIndex: tmuxState.activeWindowIndex,
        onResize: (selectedWindow) {
          Navigator.pop(dialogContext);
          actions.onResizeWindow(selectedWindow);
        },
      );
    },
  ).then((_) => actions.onSheetClosed());
}
