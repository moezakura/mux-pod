import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tmux/tmux_parser.dart';

/// Tmux状態
class TmuxState {
  final List<TmuxSession> sessions;
  final String? activeSessionName;
  final int? activeWindowIndex;
  final int? activePaneIndex;
  final String? activePaneId;
  final bool isLoading;
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
      activeWindowIndex: clearActiveWindowIndex ? null : (activeWindowIndex ?? this.activeWindowIndex),
      activePaneIndex: clearActivePaneIndex ? null : (activePaneIndex ?? this.activePaneIndex),
      activePaneId: clearActivePaneId ? null : (activePaneId ?? this.activePaneId),
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  /// アクティブセッションを取得
  TmuxSession? get activeSession {
    if (activeSessionName == null) return null;
    try {
      return sessions.firstWhere((s) => s.name == activeSessionName);
    } catch (e) {
      return null;
    }
  }

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

/// Tmuxセッションを管理するNotifier
class TmuxNotifier extends Notifier<TmuxState> {
  @override
  TmuxState build() {
    return const TmuxState();
  }

  /// セッション一覧を更新
  void updateSessions(List<TmuxSession> sessions) {
    state = state.copyWith(sessions: sessions, error: null);
  }

  /// セッション一覧を解析して更新
  void parseAndUpdateSessions(String output) {
    try {
      final sessions = TmuxParser.parseSessions(output);
      state = state.copyWith(sessions: sessions, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// フルツリーを解析して更新
  void parseAndUpdateFullTree(String output) {
    try {
      final sessions = TmuxParser.parseFullTree(output);
      state = state.copyWith(sessions: sessions, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// アクティブセッションを設定
  void setActiveSession(String sessionName) {
    // セッション内の最初のアクティブウィンドウとペインを自動選択
    final session = state.sessions.where((s) => s.name == sessionName).firstOrNull;
    final activeWindow = session?.windows.where((w) => w.active).firstOrNull ?? session?.windows.firstOrNull;
    final activePane = activeWindow?.panes.where((p) => p.active).firstOrNull ?? activeWindow?.panes.firstOrNull;

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

  /// アクティブウィンドウを設定
  void setActiveWindow(int windowIndex) {
    // ウィンドウ内の最初のアクティブペインを自動選択
    final session = state.activeSession;
    final window = session?.windows.where((w) => w.index == windowIndex).firstOrNull;
    final activePane = window?.panes.where((p) => p.active).firstOrNull ?? window?.panes.firstOrNull;

    state = state.copyWith(
      activeWindowIndex: windowIndex,
      activePaneIndex: activePane?.index,
      activePaneId: activePane?.id,
      clearActivePaneIndex: activePane == null,
      clearActivePaneId: activePane == null,
    );
  }

  /// アクティブペインを設定（pane index）
  void setActivePaneByIndex(int paneIndex, {String? paneId}) {
    state = state.copyWith(
      activePaneIndex: paneIndex,
      activePaneId: paneId,
    );
  }

  /// アクティブペインを設定（pane ID）
  void setActivePane(String paneId) {
    // paneIdからindexを取得
    final window = state.activeWindow;
    final pane = window?.panes.where((p) => p.id == paneId).firstOrNull;
    state = state.copyWith(
      activePaneId: paneId,
      activePaneIndex: pane?.index,
    );
  }

  /// カーソル位置を更新
  void updateCursorPosition(String paneId, int x, int y) {
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

  /// 現在のポーリング対象のtmuxターゲット文字列を取得
  /// format: session:window.pane
  String? get currentTarget {
    final session = state.activeSessionName;
    final window = state.activeWindowIndex;
    final pane = state.activePaneIndex;
    if (session == null || window == null || pane == null) return null;
    return '$session:$window.$pane';
  }

  /// ローディング状態を設定
  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  /// エラーを設定
  void setError(String? error) {
    state = state.copyWith(error: error);
  }

  /// 状態をクリア
  void clear() {
    state = const TmuxState();
  }
}

/// Tmuxプロバイダー
final tmuxProvider = NotifierProvider<TmuxNotifier, TmuxState>(() {
  return TmuxNotifier();
});
