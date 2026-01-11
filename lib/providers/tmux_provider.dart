import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tmux/tmux_parser.dart';

/// Tmux状態
class TmuxState {
  final List<TmuxSession> sessions;
  final String? activeSessionName;
  final int? activeWindowIndex;
  final String? activePaneId;
  final bool isLoading;
  final String? error;

  const TmuxState({
    this.sessions = const [],
    this.activeSessionName,
    this.activeWindowIndex,
    this.activePaneId,
    this.isLoading = false,
    this.error,
  });

  TmuxState copyWith({
    List<TmuxSession>? sessions,
    String? activeSessionName,
    int? activeWindowIndex,
    String? activePaneId,
    bool? isLoading,
    String? error,
  }) {
    return TmuxState(
      sessions: sessions ?? this.sessions,
      activeSessionName: activeSessionName ?? this.activeSessionName,
      activeWindowIndex: activeWindowIndex ?? this.activeWindowIndex,
      activePaneId: activePaneId ?? this.activePaneId,
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
    state = state.copyWith(
      activeSessionName: sessionName,
      activeWindowIndex: null,
      activePaneId: null,
    );
  }

  /// アクティブウィンドウを設定
  void setActiveWindow(int windowIndex) {
    state = state.copyWith(
      activeWindowIndex: windowIndex,
      activePaneId: null,
    );
  }

  /// アクティブペインを設定
  void setActivePane(String paneId) {
    state = state.copyWith(activePaneId: paneId);
  }

  /// アクティブなセッション/ウィンドウ/ペインを一括設定
  void setActive({
    String? sessionName,
    int? windowIndex,
    String? paneId,
  }) {
    state = state.copyWith(
      activeSessionName: sessionName,
      activeWindowIndex: windowIndex,
      activePaneId: paneId,
    );
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
