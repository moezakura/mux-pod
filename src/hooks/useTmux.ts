/**
 * useTmux Hook
 *
 * tmuxセッションのナビゲーションと管理を行うカスタムフック。
 */
import { useCallback, useEffect, useMemo, useRef } from 'react';
import { useSessionStore } from '@/stores/sessionStore';
import { TmuxCommands } from '@/services/tmux/commands';
import type { ISSHClient } from '@/services/ssh/client';
import type { TmuxSession, TmuxWindow, TmuxPane } from '@/types/tmux';

/**
 * useTmuxの戻り値
 */
export interface UseTmuxResult {
  /** セッション一覧 */
  sessions: TmuxSession[];
  /** 選択中のセッション */
  selectedSession: string | null;
  /** 選択中のウィンドウ */
  selectedWindow: number | null;
  /** 選択中のペイン */
  selectedPane: number | null;
  /** ローディング中 */
  loading: boolean;
  /** エラー */
  error: string | null;
  /** セッションを選択する */
  selectSession: (name: string) => void;
  /** ウィンドウを選択する */
  selectWindow: (index: number) => void;
  /** ペインを選択する */
  selectPane: (index: number) => void;
  /** セッション一覧を更新する */
  refreshSessions: () => Promise<void>;
  /** 指定セッションのウィンドウを更新する */
  refreshWindows: (sessionName: string) => Promise<TmuxWindow[]>;
  /** 指定ウィンドウのペインを更新する */
  refreshPanes: (sessionName: string, windowIndex: number) => Promise<TmuxPane[]>;
  /** 現在選択中のセッションオブジェクト */
  currentSession: TmuxSession | undefined;
  /** 現在選択中のウィンドウオブジェクト */
  currentWindow: TmuxWindow | undefined;
  /** 現在選択中のペインオブジェクト */
  currentPane: TmuxPane | undefined;
}

/**
 * tmuxセッションを管理するフック
 */
export function useTmux(
  sshClient: ISSHClient | null,
  connectionId: string
): UseTmuxResult {
  const tmuxRef = useRef<TmuxCommands | null>(null);

  const {
    sessions: allSessions,
    selectedSession,
    selectedWindow,
    selectedPane,
    loading,
    error,
    setSessions,
    selectSession,
    selectWindow,
    selectPane,
    setLoading,
    setError,
    autoSelect,
  } = useSessionStore();

  const sessions = useMemo(
    () => allSessions[connectionId] ?? [],
    [allSessions, connectionId]
  );

  // TmuxCommandsインスタンスの初期化
  useEffect(() => {
    if (sshClient) {
      tmuxRef.current = new TmuxCommands(sshClient);
    } else {
      tmuxRef.current = null;
    }
  }, [sshClient]);

  // セッション一覧を更新
  const refreshSessions = useCallback(async (): Promise<void> => {
    if (!tmuxRef.current) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const newSessions = await tmuxRef.current.listSessions();

      // 各セッションのウィンドウも取得
      for (const session of newSessions) {
        session.windows = await tmuxRef.current.listWindows(session.name);

        // 各ウィンドウのペインも取得
        for (const window of session.windows) {
          window.panes = await tmuxRef.current.listPanes(session.name, window.index);
        }
      }

      setSessions(connectionId, newSessions);

      // 何も選択されていなければ自動選択
      if (!selectedSession && newSessions.length > 0) {
        autoSelect(connectionId);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [connectionId, selectedSession, setSessions, autoSelect, setLoading, setError]);

  // 指定セッションのウィンドウを更新
  const refreshWindows = useCallback(
    async (sessionName: string): Promise<TmuxWindow[]> => {
      if (!tmuxRef.current) {
        return [];
      }

      try {
        const windows = await tmuxRef.current.listWindows(sessionName);

        // ペインも取得
        for (const window of windows) {
          window.panes = await tmuxRef.current.listPanes(sessionName, window.index);
        }

        // セッションを更新
        const updatedSessions = sessions.map((s) =>
          s.name === sessionName ? { ...s, windows } : s
        );
        setSessions(connectionId, updatedSessions);

        return windows;
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown error';
        setError(message);
        return [];
      }
    },
    [connectionId, sessions, setSessions, setError]
  );

  // 指定ウィンドウのペインを更新
  const refreshPanes = useCallback(
    async (sessionName: string, windowIndex: number): Promise<TmuxPane[]> => {
      if (!tmuxRef.current) {
        return [];
      }

      try {
        const panes = await tmuxRef.current.listPanes(sessionName, windowIndex);

        // セッションを更新
        const updatedSessions = sessions.map((s) => {
          if (s.name !== sessionName) {
            return s;
          }
          return {
            ...s,
            windows: s.windows.map((w) =>
              w.index === windowIndex ? { ...w, panes } : w
            ),
          };
        });
        setSessions(connectionId, updatedSessions);

        return panes;
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown error';
        setError(message);
        return [];
      }
    },
    [connectionId, sessions, setSessions, setError]
  );

  // 現在選択中のオブジェクトを取得
  const currentSession = selectedSession
    ? sessions.find((s) => s.name === selectedSession)
    : undefined;

  const currentWindow =
    currentSession && selectedWindow !== null
      ? currentSession.windows.find((w) => w.index === selectedWindow)
      : undefined;

  const currentPane =
    currentWindow && selectedPane !== null
      ? currentWindow.panes.find((p) => p.index === selectedPane)
      : undefined;

  // 接続時にセッション一覧を取得
  useEffect(() => {
    if (sshClient?.isConnected()) {
      refreshSessions();
    }
  }, [sshClient, refreshSessions]);

  return {
    sessions,
    selectedSession,
    selectedWindow,
    selectedPane,
    loading,
    error,
    selectSession,
    selectWindow,
    selectPane,
    refreshSessions,
    refreshWindows,
    refreshPanes,
    currentSession,
    currentWindow,
    currentPane,
  };
}
