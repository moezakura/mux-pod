/**
 * 接続ストア
 *
 * SSH接続設定の管理と永続化を行うZustandストア。
 */
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type {
  Connection,
  ConnectionInput,
  ConnectionState,
  DisconnectReason,
  ConnectionStatus,
} from '@/types/connection';
import { DEFAULT_CONNECTION, DEFAULT_RECONNECT_SETTINGS } from '@/types/connection';

/**
 * UUID v4を生成する
 */
function generateId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * 接続ストアの状態
 */
interface ConnectionStoreState {
  /** 保存された接続一覧 */
  connections: Connection[];
  /** 接続のランタイム状態 */
  connectionStates: Record<string, ConnectionState>;
  /** アクティブな接続ID */
  activeConnectionId: string | null;
}

/**
 * 再接続設定の更新パラメータ
 */
interface ReconnectSettingsUpdate {
  autoReconnect?: boolean;
  maxReconnectAttempts?: number;
  reconnectInterval?: number;
}

/**
 * 再接続試行結果の記録パラメータ
 */
interface ReconnectAttemptResult {
  attemptNumber: number;
  result: 'success' | 'failed' | 'cancelled';
  error?: string;
}

/**
 * 接続ストアのアクション
 */
interface ConnectionStoreActions {
  /** 接続を追加する */
  addConnection: (input: ConnectionInput) => string;
  /** 接続を更新する */
  updateConnection: (id: string, updates: Partial<Connection>) => void;
  /** 接続を削除する */
  removeConnection: (id: string) => void;
  /** 接続のランタイム状態を設定する */
  setConnectionState: (id: string, state: Partial<ConnectionState>) => void;
  /** アクティブな接続を設定する */
  setActiveConnection: (id: string | null) => void;
  /** 接続を取得する */
  getConnection: (id: string) => Connection | undefined;
  /** すべての接続をクリアする */
  clearAllConnections: () => void;

  // 再接続関連アクション
  /** 接続の再接続設定を更新する */
  updateReconnectSettings: (id: string, settings: ReconnectSettingsUpdate) => void;
  /** 切断状態に更新する */
  setDisconnected: (id: string, reason: DisconnectReason) => void;
  /** 再接続中状態に更新する */
  setReconnecting: (id: string, attemptNumber: number, maxAttempts: number) => void;
  /** 再接続試行結果を記録する */
  recordReconnectAttempt: (id: string, result: ReconnectAttemptResult) => void;
  /** 再接続状態をクリアする */
  clearReconnectState: (id: string) => void;
}

/**
 * 接続ストア
 */
export const useConnectionStore = create<ConnectionStoreState & ConnectionStoreActions>()(
  persist(
    (set, get) => ({
      // 初期状態
      connections: [],
      connectionStates: {},
      activeConnectionId: null,

      // 接続を追加する
      addConnection: (input: ConnectionInput): string => {
        const id = generateId();
        const now = Date.now();

        const connection: Connection = {
          ...DEFAULT_CONNECTION,
          ...input,
          id,
          createdAt: now,
          updatedAt: now,
        } as Connection;

        set((state) => ({
          connections: [...state.connections, connection],
          connectionStates: {
            ...state.connectionStates,
            [id]: {
              connectionId: id,
              status: 'disconnected',
            },
          },
        }));

        return id;
      },

      // 接続を更新する
      updateConnection: (id: string, updates: Partial<Connection>): void => {
        set((state) => ({
          connections: state.connections.map((conn) =>
            conn.id === id
              ? { ...conn, ...updates, updatedAt: Date.now() }
              : conn
          ),
        }));
      },

      // 接続を削除する
      removeConnection: (id: string): void => {
        set((state) => {
          const { [id]: _, ...remainingStates } = state.connectionStates;
          return {
            connections: state.connections.filter((conn) => conn.id !== id),
            connectionStates: remainingStates,
            activeConnectionId:
              state.activeConnectionId === id ? null : state.activeConnectionId,
          };
        });
      },

      // 接続のランタイム状態を設定する
      setConnectionState: (id: string, stateUpdate: Partial<ConnectionState>): void => {
        set((state) => ({
          connectionStates: {
            ...state.connectionStates,
            [id]: {
              connectionId: id,
              status: 'disconnected',
              ...state.connectionStates[id],
              ...stateUpdate,
            },
          },
        }));
      },

      // アクティブな接続を設定する
      setActiveConnection: (id: string | null): void => {
        set({ activeConnectionId: id });
      },

      // 接続を取得する
      getConnection: (id: string): Connection | undefined => {
        return get().connections.find((conn) => conn.id === id);
      },

      // すべての接続をクリアする
      clearAllConnections: (): void => {
        set({
          connections: [],
          connectionStates: {},
          activeConnectionId: null,
        });
      },

      // 再接続設定を更新する
      updateReconnectSettings: (id: string, settings: ReconnectSettingsUpdate): void => {
        set((state) => ({
          connections: state.connections.map((conn) =>
            conn.id === id
              ? { ...conn, ...settings, updatedAt: Date.now() }
              : conn
          ),
        }));
      },

      // 切断状態に更新する
      setDisconnected: (id: string, reason: DisconnectReason): void => {
        const now = Date.now();
        set((state) => ({
          connectionStates: {
            ...state.connectionStates,
            [id]: {
              connectionId: id,
              ...state.connectionStates[id],
              status: 'disconnected' as ConnectionStatus,
              disconnectedAt: now,
              disconnectReason: reason,
              reconnectAttempt: undefined,
            },
          },
        }));
      },

      // 再接続中状態に更新する
      setReconnecting: (id: string, attemptNumber: number, maxAttempts: number): void => {
        const now = Date.now();
        set((state) => {
          const currentState = state.connectionStates[id];
          const existingAttempt = currentState?.reconnectAttempt;

          return {
            connectionStates: {
              ...state.connectionStates,
              [id]: {
                connectionId: id,
                ...currentState,
                status: 'reconnecting' as ConnectionStatus,
                reconnectAttempt: {
                  startedAt: existingAttempt?.startedAt ?? now,
                  attemptNumber,
                  maxAttempts,
                  history: existingAttempt?.history ?? [],
                },
              },
            },
          };
        });
      },

      // 再接続試行結果を記録する
      recordReconnectAttempt: (id: string, result: ReconnectAttemptResult): void => {
        const now = Date.now();
        set((state) => {
          const currentState = state.connectionStates[id];
          const existingAttempt = currentState?.reconnectAttempt;

          if (!existingAttempt) return state;

          return {
            connectionStates: {
              ...state.connectionStates,
              [id]: {
                ...currentState,
                reconnectAttempt: {
                  ...existingAttempt,
                  history: [
                    ...existingAttempt.history,
                    {
                      attemptNumber: result.attemptNumber,
                      attemptedAt: now,
                      result: result.result,
                      error: result.error,
                    },
                  ],
                },
              },
            },
          };
        });
      },

      // 再接続状態をクリアする
      clearReconnectState: (id: string): void => {
        set((state) => {
          const currentState = state.connectionStates[id];
          if (!currentState) return state;

          return {
            connectionStates: {
              ...state.connectionStates,
              [id]: {
                ...currentState,
                reconnectAttempt: undefined,
              },
            },
          };
        });
      },
    }),
    {
      name: 'muxpod-connections',
      storage: createJSONStorage(() => AsyncStorage),
      // ランタイム状態は永続化しない
      partialize: (state) => ({
        connections: state.connections,
      }),
    }
  )
);

/**
 * 接続状態のセレクター
 */
export const selectConnectionState = (
  state: ConnectionStoreState,
  connectionId: string
): ConnectionState => {
  return (
    state.connectionStates[connectionId] ?? {
      connectionId,
      status: 'disconnected',
    }
  );
};

/**
 * アクティブな接続のセレクター
 */
export const selectActiveConnection = (
  state: ConnectionStoreState
): Connection | undefined => {
  if (!state.activeConnectionId) return undefined;
  return state.connections.find((conn) => conn.id === state.activeConnectionId);
};
