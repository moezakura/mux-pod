/**
 * useSSH Hook
 *
 * SSH接続の管理とライフサイクルを扱うカスタムフック。
 */
import { useCallback, useRef, useEffect, useState } from 'react';
import { useConnectionStore } from '@/stores/connectionStore';
import {
  SSHClient,
  type ISSHClient,
  type SSHConnectOptions,
  type SSHEvents,
  SSHConnectionError,
} from '@/services/ssh/client';
import { loadPassword } from '@/services/ssh/auth';
import { getPrivateKey } from '@/services/ssh/keyManager';
import {
  trustHostKey,
  updateHostKey,
} from '@/services/ssh/knownHostManager';
import type { HostKeyType } from '@/types/sshKey';

/**
 * ホスト鍵確認の状態
 */
export interface HostKeyPromptState {
  /** ダイアログを表示中か */
  visible: boolean;
  /** 確認タイプ（unknown: 新規, changed: 変更） */
  type: 'unknown' | 'changed';
  /** ホスト名 */
  host: string;
  /** ポート番号 */
  port: number;
  /** 鍵タイプ */
  keyType: HostKeyType;
  /** 新しいフィンガープリント */
  fingerprint: string;
  /** 以前のフィンガープリント（changedの場合） */
  previousFingerprint?: string;
}

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
  /** ホスト鍵確認状態 */
  hostKeyPrompt: HostKeyPromptState | null;
  /** ホスト鍵を信頼する */
  trustCurrentHostKey: () => Promise<void>;
  /** ホスト鍵確認をキャンセル */
  cancelHostKeyPrompt: () => void;
}

/**
 * ホスト鍵検証に使用する情報
 */
interface PendingHostKeyInfo {
  connectionId: string;
  options: SSHConnectOptions;
  host: string;
  port: number;
  keyType: HostKeyType;
  publicKey: string;
  fingerprint: string;
}

/**
 * SSH接続を管理するフック
 */
export function useSSH(events?: Partial<SSHEvents>): UseSSHResult {
  const clientRef = useRef<ISSHClient | null>(null);
  const connectionIdRef = useRef<string | null>(null);

  // ホスト鍵確認状態
  const [hostKeyPrompt, setHostKeyPrompt] = useState<HostKeyPromptState | null>(null);
  const pendingHostKeyRef = useRef<PendingHostKeyInfo | null>(null);

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
        // 認証情報を準備
        let authOptions = options ?? {};

        if (connection.authMethod === 'password' && !authOptions.password) {
          // パスワードを読み込む（指定されていない場合）
          const storedPassword = await loadPassword(connectionId);
          if (storedPassword) {
            authOptions = { ...authOptions, password: storedPassword };
          }
        } else if (connection.authMethod === 'key' && connection.keyId && !authOptions.privateKey) {
          // 秘密鍵を読み込む（指定されていない場合）
          const privateKey = await getPrivateKey(connection.keyId);
          if (privateKey) {
            authOptions = { ...authOptions, privateKey };
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

  // ホスト鍵を信頼して接続を続行
  const trustCurrentHostKey = useCallback(async (): Promise<void> => {
    const pending = pendingHostKeyRef.current;
    if (!pending) {
      return;
    }

    try {
      // 新規ホストの場合は信頼リストに追加
      if (hostKeyPrompt?.type === 'unknown') {
        await trustHostKey(
          pending.host,
          pending.port,
          pending.keyType,
          pending.publicKey,
          pending.fingerprint
        );
      } else if (hostKeyPrompt?.type === 'changed') {
        // 鍵が変更された場合は更新
        await updateHostKey(
          `${pending.host}:${pending.port}`,
          pending.keyType,
          pending.publicKey,
          pending.fingerprint
        );
      }

      // ダイアログを閉じてpendingをクリア
      setHostKeyPrompt(null);
      pendingHostKeyRef.current = null;

      // 接続を再開（ホスト鍵は既に信頼済み）
      // 注意: 実際のSSH接続はライブラリのホスト鍵コールバック対応後に実装
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to trust host key';
      if (pending.connectionId) {
        setConnectionState(pending.connectionId, {
          status: 'error',
          error: message,
        });
      }
    }
  }, [hostKeyPrompt, setConnectionState]);

  // ホスト鍵確認をキャンセル
  const cancelHostKeyPrompt = useCallback((): void => {
    const pending = pendingHostKeyRef.current;

    if (pending?.connectionId) {
      setConnectionState(pending.connectionId, {
        status: 'disconnected',
      });
      connectionIdRef.current = null;
    }

    setHostKeyPrompt(null);
    pendingHostKeyRef.current = null;
  }, [setConnectionState]);

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
    hostKeyPrompt,
    trustCurrentHostKey,
    cancelHostKeyPrompt,
  };
}
