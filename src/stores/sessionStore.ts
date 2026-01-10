/**
 * セッションストア
 *
 * tmuxセッション/ウィンドウ/ペインの状態を管理するZustandストア。
 */
import { create } from 'zustand';
import type { TmuxSession } from '@/types/tmux';

/**
 * セッションストアの状態
 */
interface SessionStoreState {
  /** セッション一覧 (connectionId -> sessions) */
  sessions: Record<string, TmuxSession[]>;
  /** 選択中のセッション名 */
  selectedSession: string | null;
  /** 選択中のウィンドウインデックス */
  selectedWindow: number | null;
  /** 選択中のペインインデックス */
  selectedPane: number | null;
  /** ローディング状態 */
  loading: boolean;
  /** エラー */
  error: string | null;
}

/**
 * セッションストアのアクション
 */
interface SessionStoreActions {
  /** セッション一覧を設定する */
  setSessions: (connectionId: string, sessions: TmuxSession[]) => void;
  /** セッションを選択する */
  selectSession: (name: string) => void;
  /** ウィンドウを選択する */
  selectWindow: (index: number) => void;
  /** ペインを選択する */
  selectPane: (index: number) => void;
  /** 選択をクリアする */
  clearSelection: () => void;
  /** セッションをクリアする */
  clearSessions: (connectionId: string) => void;
  /** ローディング状態を設定する */
  setLoading: (loading: boolean) => void;
  /** エラーを設定する */
  setError: (error: string | null) => void;
  /** 最初のセッション/ウィンドウ/ペインを自動選択する */
  autoSelect: (connectionId: string) => void;
}

/**
 * セッションストア
 */
export const useSessionStore = create<SessionStoreState & SessionStoreActions>((set, get) => ({
  // 初期状態
  sessions: {},
  selectedSession: null,
  selectedWindow: null,
  selectedPane: null,
  loading: false,
  error: null,

  // セッション一覧を設定する
  setSessions: (connectionId: string, sessions: TmuxSession[]): void => {
    set((state) => ({
      sessions: {
        ...state.sessions,
        [connectionId]: sessions,
      },
    }));
  },

  // セッションを選択する
  selectSession: (name: string): void => {
    set({
      selectedSession: name,
      selectedWindow: null,
      selectedPane: null,
    });
  },

  // ウィンドウを選択する
  selectWindow: (index: number): void => {
    set({
      selectedWindow: index,
      selectedPane: null,
    });
  },

  // ペインを選択する
  selectPane: (index: number): void => {
    set({ selectedPane: index });
  },

  // 選択をクリアする
  clearSelection: (): void => {
    set({
      selectedSession: null,
      selectedWindow: null,
      selectedPane: null,
    });
  },

  // セッションをクリアする
  clearSessions: (connectionId: string): void => {
    set((state) => {
      const { [connectionId]: _, ...remaining } = state.sessions;
      return { sessions: remaining };
    });
  },

  // ローディング状態を設定する
  setLoading: (loading: boolean): void => {
    set({ loading });
  },

  // エラーを設定する
  setError: (error: string | null): void => {
    set({ error });
  },

  // 最初のセッション/ウィンドウ/ペインを自動選択する
  autoSelect: (connectionId: string): void => {
    const sessions = get().sessions[connectionId];
    if (!sessions || sessions.length === 0) {
      return;
    }

    const firstSession = sessions[0];
    if (!firstSession) {
      return;
    }

    set({
      selectedSession: firstSession.name,
      selectedWindow: firstSession.windows[0]?.index ?? 0,
      selectedPane: firstSession.windows[0]?.panes[0]?.index ?? 0,
    });
  },
}));

/**
 * 現在選択中のセッションを取得するセレクター
 */
export const selectCurrentSession = (
  state: SessionStoreState,
  connectionId: string
): TmuxSession | undefined => {
  const sessions = state.sessions[connectionId];
  if (!sessions || !state.selectedSession) {
    return undefined;
  }
  return sessions.find((s) => s.name === state.selectedSession);
};
