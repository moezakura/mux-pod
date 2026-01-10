/**
 * useSSH Hook
 *
 * SSH接続の管理とライフサイクルを扱うカスタムフック。
 */
import { useCallback, useRef, useEffect } from 'react';
import { useConnectionStore } from '@/stores/connectionStore';
import {
  SSHClient,
  type ISSHClient,
  type SSHConnectOptions,
  type SSHEvents,
  SSHConnectionError,
} from '@/services/ssh/client';
import { loadPassword } from '@/services/ssh/auth';

/**
 * useSSHの戻り値
 */
export interface UseSSHResult {
  /** SSHクライアント */
  client: ISSHClient | null;
  /** 接続を開始する */
  connect: (connectionId: string, options?: SSHConnectOptions) => Promise<void>;
  /** 接続を切断する */
  disconnect: () => Promise<void>;
  /** コマンドを実行する */
  exec: (command: string) => Promise<string>;
  /** シェルを開始する */
  startShell: () => Promise<void>;
  /** シェルに書き込む */
  write: (data: string) => Promise<void>;
  /** 接続中かどうか */
  isConnected: boolean;
  /** 現在の接続ID */
  connectionId: string | null;
  /** エラーメッセージ */
  error: string | null;
  /** 接続中かどうか */
  isConnecting: boolean;
}

/**
 * SSH接続を管理するフック
 */
export function useSSH(events?: Partial<SSHEvents>): UseSSHResult {
  const clientRef = useRef<ISSHClient | null>(null);
  const connectionIdRef = useRef<string | null>(null);

  const {
    getConnection,
    setConnectionState,
    setActiveConnection,
    connectionStates,
    activeConnectionId,
  } = useConnectionStore();

  // 現在の接続状態を取得
  const currentState = activeConnectionId
    ? connectionStates[activeConnectionId]
    : null;

  const isConnected = currentState?.status === 'connected';
  const isConnecting = currentState?.status === 'connecting';
  const error = currentState?.error ?? null;

  // イベントハンドラの設定
  useEffect(() => {
    if (clientRef.current && events) {
      clientRef.current.setEventHandlers({
        ...events,
        onClose: () => {
          if (connectionIdRef.current) {
            setConnectionState(connectionIdRef.current, {
              status: 'disconnected',
            });
            setActiveConnection(null);
          }
          events.onClose?.();
        },
        onError: (err) => {
          if (connectionIdRef.current) {
            setConnectionState(connectionIdRef.current, {
              status: 'error',
              error: err.message,
            });
          }
          events.onError?.(err);
        },
      });
    }
  }, [events, setConnectionState, setActiveConnection]);

  // 接続を開始する
  const connect = useCallback(
    async (connectionId: string, options?: SSHConnectOptions): Promise<void> => {
      const connection = getConnection(connectionId);
      if (!connection) {
        throw new SSHConnectionError(`Connection not found: ${connectionId}`);
      }

      // 既存の接続があれば切断
      if (clientRef.current) {
        await clientRef.current.disconnect();
      }

      // 接続状態を更新
      setConnectionState(connectionId, { status: 'connecting' });
      connectionIdRef.current = connectionId;

      try {
        // パスワードを読み込む（指定されていない場合）
        let authOptions = options ?? {};
        if (connection.authMethod === 'password' && !authOptions.password) {
          const storedPassword = await loadPassword(connectionId);
          if (storedPassword) {
            authOptions = { ...authOptions, password: storedPassword };
          }
        }

        // 新しいクライアントを作成して接続
        const client = new SSHClient();
        if (events) {
          client.setEventHandlers(events);
        }

        await client.connect(connection, authOptions);

        clientRef.current = client;
        setConnectionState(connectionId, {
          status: 'connected',
          connectedAt: Date.now(),
        });
        setActiveConnection(connectionId);

        // 最終接続日時を更新
        useConnectionStore.getState().updateConnection(connectionId, {
          lastConnected: Date.now(),
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown error';
        setConnectionState(connectionId, {
          status: 'error',
          error: message,
        });
        connectionIdRef.current = null;
        throw err;
      }
    },
    [getConnection, setConnectionState, setActiveConnection, events]
  );

  // 接続を切断する
  const disconnect = useCallback(async (): Promise<void> => {
    if (clientRef.current) {
      await clientRef.current.disconnect();
      clientRef.current = null;
    }

    if (connectionIdRef.current) {
      setConnectionState(connectionIdRef.current, {
        status: 'disconnected',
        connectedAt: undefined,
      });
      connectionIdRef.current = null;
    }

    setActiveConnection(null);
  }, [setConnectionState, setActiveConnection]);

  // コマンドを実行する
  const exec = useCallback(async (command: string): Promise<string> => {
    if (!clientRef.current) {
      throw new SSHConnectionError('Not connected');
    }
    return await clientRef.current.exec(command);
  }, []);

  // シェルを開始する
  const startShell = useCallback(async (): Promise<void> => {
    if (!clientRef.current) {
      throw new SSHConnectionError('Not connected');
    }
    await clientRef.current.startShell();
  }, []);

  // シェルに書き込む
  const write = useCallback(async (data: string): Promise<void> => {
    if (!clientRef.current) {
      throw new SSHConnectionError('Not connected');
    }
    await clientRef.current.write(data);
  }, []);

  // クリーンアップ
  useEffect(() => {
    return () => {
      if (clientRef.current) {
        clientRef.current.disconnect();
      }
    };
  }, []);

  return {
    client: clientRef.current,
    connect,
    disconnect,
    exec,
    startShell,
    write,
    isConnected,
    connectionId: connectionIdRef.current,
    error,
    isConnecting,
  };
}
