import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tmux/tmux_facade.dart';
import '../services/tmux/tmux_models.dart';

// inventory: PROV-TMUX-001
/// Tmux状態
class TmuxState {
  // inventory: PROV-TMUX-002
  // inventory: LEGACY-0163
  final List<TmuxSession> sessions;
  // inventory: PROV-TMUX-003
  // inventory: LEGACY-0164
  final String? activeSessionName;
  // inventory: PROV-TMUX-004
  // inventory: LEGACY-0165
  final int? activeWindowIndex;
  // inventory: PROV-TMUX-005
  // inventory: LEGACY-0166
  final int? activePaneIndex;
  // inventory: PROV-TMUX-006
  // inventory: LEGACY-0167
  final String? activePaneId;
  // inventory: PROV-TMUX-007
  // inventory: LEGACY-0168
  final bool isLoading;
  // inventory: PROV-TMUX-008
  // inventory: LEGACY-0169
  final String? error;

  const TmuxState({
    this.sessions = const [],
    this.activeSessionName,
    this.activeWindowIndex,
    this.activePaneIndex,
    this.activePaneId,
    this.isLoading = false,
    this.error,
  });

  // inventory: PROV-TMUX-009
  // inventory: LEGACY-0170
  TmuxState copyWith({
    List<TmuxSession>? sessions,
    String? activeSessionName,
    int? activeWindowIndex,
    int? activePaneIndex,
    String? activePaneId,
    bool? isLoading,
    String? error,
    bool clearActiveWindowIndex = false,
    bool clearActivePaneIndex = false,
    bool clearActivePaneId = false,
  }) {
    return TmuxState(
      sessions: sessions ?? this.sessions,
      activeSessionName: activeSessionName ?? this.activeSessionName,
      activeWindowIndex: clearActiveWindowIndex
          ? null
          : (activeWindowIndex ?? this.activeWindowIndex),
      activePaneIndex: clearActivePaneIndex
          ? null
          : (activePaneIndex ?? this.activePaneIndex),
      activePaneId: clearActivePaneId
          ? null
          : (activePaneId ?? this.activePaneId),
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  // inventory: PROV-TMUX-010
  /// アクティブセッションを取得
  TmuxSession? get activeSession {
    if (activeSessionName == null) return null;
    try {
      return sessions.firstWhere((s) => s.name == activeSessionName);
    } catch (e) {
      return null;
    }
  }

  // inventory: PROV-TMUX-011
  /// アクティブウィンドウを取得
  TmuxWindow? get activeWindow {
    final session = activeSession;
    if (session == null || activeWindowIndex == null) return null;
    try {
      return session.windows.firstWhere((w) => w.index == activeWindowIndex);
    } catch (e) {
      return null;
    }
  }

  // inventory: PROV-TMUX-012
  /// アクティブペインを取得
  TmuxPane? get activePane {
    final window = activeWindow;
    if (window == null || activePaneId == null) return null;
    try {
      return window.panes.firstWhere((p) => p.id == activePaneId);
    } catch (e) {
      return null;
    }
  }
}

// inventory: PROV-TMUX-013
/// Tmuxセッションを管理するNotifier
class TmuxNotifier extends Notifier<TmuxState> {
  @override
  // inventory: PROV-TMUX-014
  // inventory: LEGACY-0171
  TmuxState build() {
    return const TmuxState();
  }

  // inventory: PROV-TMUX-015
  // inventory: LEGACY-0172
  /// セッション一覧を更新
  void updateSessions(List<TmuxSession> sessions) {
    state = state.copyWith(sessions: sessions, error: null);
  }

  // inventory: PROV-TMUX-016
  // inventory: LEGACY-0173
  /// セッション一覧を解析して更新
  void parseAndUpdateSessions(String output) {
    try {
      final sessions = tmuxFacade.parseSessions(output);
      state = state.copyWith(sessions: sessions, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // inventory: PROV-TMUX-017
  // inventory: LEGACY-0174
  /// フルツリーを解析して更新
  void parseAndUpdateFullTree(String output) {
    try {
      final sessions = tmuxFacade.parseFullTree(output);
      state = state.copyWith(sessions: sessions, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // inventory: PROV-TMUX-018
  // inventory: LEGACY-0175
  /// アクティブセッションを設定
  void setActiveSession(String sessionName) {
    // セッション内の最初のアクティブウィンドウとペインを自動選択
    final session = state.sessions
        .where((s) => s.name == sessionName)
        .firstOrNull;
    final activeWindow =
        session?.windows.where((w) => w.active).firstOrNull ??
        session?.windows.firstOrNull;
    final activePane =
        activeWindow?.panes.where((p) => p.active).firstOrNull ??
        activeWindow?.panes.firstOrNull;

    state = state.copyWith(
      activeSessionName: sessionName,
      activeWindowIndex: activeWindow?.index,
      activePaneIndex: activePane?.index,
      activePaneId: activePane?.id,
      clearActiveWindowIndex: activeWindow == null,
      clearActivePaneIndex: activePane == null,
      clearActivePaneId: activePane == null,
    );
  }

  // inventory: PROV-TMUX-019
  // inventory: LEGACY-0176
  /// アクティブウィンドウを設定
  void setActiveWindow(int windowIndex) {
    // ウィンドウ内の最初のアクティブペインを自動選択
    final session = state.activeSession;
    final window = session?.windows
        .where((w) => w.index == windowIndex)
        .firstOrNull;
    final activePane =
        window?.panes.where((p) => p.active).firstOrNull ??
        window?.panes.firstOrNull;

    state = state.copyWith(
      activeWindowIndex: windowIndex,
      activePaneIndex: activePane?.index,
      activePaneId: activePane?.id,
      clearActivePaneIndex: activePane == null,
      clearActivePaneId: activePane == null,
    );
  }

  // inventory: PROV-TMUX-020
  // inventory: LEGACY-0177
  /// アクティブペインを設定（pane index）
  void setActivePaneByIndex(int paneIndex, {String? paneId}) {
    state = state.copyWith(activePaneIndex: paneIndex, activePaneId: paneId);
  }

  // inventory: PROV-TMUX-021
  // inventory: LEGACY-0178
  /// アクティブペインを設定（pane ID）
  void setActivePane(String paneId) {
    // paneIdからindexを取得
    final window = state.activeWindow;
    final pane = window?.panes.where((p) => p.id == paneId).firstOrNull;
    state = state.copyWith(activePaneId: paneId, activePaneIndex: pane?.index);
  }

  // inventory: PROV-TMUX-022
  // inventory: LEGACY-0179
  /// カーソル位置を更新
  void updateCursorPosition(String paneId, int x, int y) {
    // 変更がない場合はディープコピーを回避してスキップ
    final currentPane = state.activePane;
    if (currentPane == null || currentPane.id != paneId) return;
    if (currentPane.cursorX == x && currentPane.cursorY == y) return;

    final sessions = state.sessions.map((session) {
      final windows = session.windows.map((window) {
        final panes = window.panes.map((pane) {
          if (pane.id == paneId) {
            return pane.copyWith(cursorX: x, cursorY: y);
          }
          return pane;
        }).toList();
        return window.copyWith(panes: panes);
      }).toList();
      return session.copyWith(windows: windows);
    }).toList();

    state = state.copyWith(sessions: sessions);
  }

  // inventory: PROV-TMUX-023
  // inventory: LEGACY-0180
  /// アクティブなセッション/ウィンドウ/ペインを一括設定
  void setActive({
    String? sessionName,
    int? windowIndex,
    int? paneIndex,
    String? paneId,
  }) {
    state = state.copyWith(
      activeSessionName: sessionName,
      activeWindowIndex: windowIndex,
      activePaneIndex: paneIndex,
      activePaneId: paneId,
    );
  }

  // inventory: PROV-TMUX-024
  /// 現在のポーリング対象のtmuxターゲット文字列を取得
  ///
  /// ペインID（%N）を使用し、他クライアントによる split/kill で
  /// インデックスがずれても対象ペインが変わらないようにする。
  String? get currentTarget {
    final paneId = state.activePaneId;
    if (paneId == null) return null;
    return paneId;
  }

  // inventory: PROV-TMUX-025
  // inventory: LEGACY-0181
  /// ローディング状態を設定
  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  // inventory: PROV-TMUX-026
  // inventory: LEGACY-0182
  /// エラーを設定
  void setError(String? error) {
    state = state.copyWith(error: error);
  }

  // inventory: PROV-TMUX-027
  // inventory: LEGACY-0183
  /// 状態をクリア
  void clear() {
    state = const TmuxState();
  }
}

// inventory: PROV-TMUX-028
/// Tmuxプロバイダー
final tmuxProvider = NotifierProvider<TmuxNotifier, TmuxState>(() {
  return TmuxNotifier();
});
