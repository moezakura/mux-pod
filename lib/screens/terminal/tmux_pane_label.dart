import '../../providers/tmux_provider.dart';
import '../../services/backend/domain/multiplexer_pane.dart';
import '../../services/backend/domain/multiplexer_window.dart';
import '../../services/tmux/tmux_models.dart';
import '../../l10n/app_localizations.dart';

/// [TmuxState] のツリーから pane ID に一致する [TmuxPane] を引き当てる（T2）。
TmuxPane? findTmuxPaneIn(TmuxState tmuxState, String paneId) {
  for (final session in tmuxState.sessions) {
    for (final window in session.windows) {
      for (final pane in window.panes) {
        if (pane.id == paneId) return pane;
      }
    }
  }
  return null;
}

/// tmux の pane 表示名（title → currentCommand → 'Pane N' の既存ルール・Q1）。
///
/// ツリーから引き当てできない pane ID は 'Pane 0' を返す
/// （防御的フォールバック。実際にはシートの pane は同一ツリー由来のため不発）。
String tmuxPaneLabelFor(
  TmuxState tmuxState,
  String paneId,
  AppLocalizations l10n,
) {
  final pane = findTmuxPaneIn(tmuxState, paneId);
  if (pane == null) return l10n.termPaneLabel(0);
  final title = pane.title;
  if (title != null && title.isNotEmpty) return title;
  final command = pane.currentCommand;
  if (command != null && command.isNotEmpty) return command;
  return l10n.termPaneLabel(pane.index);
}

/// tmux の pane サブタイトル（'WxH'・M-2）。引き当て不可なら null。
String? tmuxPaneSubtitleFor(TmuxState tmuxState, MultiplexerPane pane) {
  return findTmuxPaneIn(tmuxState, pane.id)?.sizeString;
}

/// [session] 内で [window] に一致する [TmuxWindow] を引き当てる。
TmuxWindow? tmuxWindowOf(TmuxSession session, MultiplexerWindow window) {
  for (final tmuxWindow in session.windows) {
    if (window.id != null && tmuxWindow.id == window.id) return tmuxWindow;
    if (tmuxWindow.index == window.index) return tmuxWindow;
  }
  return null;
}
