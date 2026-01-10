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
} from '@/types/connection';
import { DEFAULT_CONNECTION } from '@/types/connection';

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
