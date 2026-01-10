/**
 * useReconnectDialog
 *
 * 再接続ダイアログの状態管理とReconnectServiceとの連携を行うフック。
 */
import { useState, useCallback, useEffect, useRef } from 'react';
import { useConnectionStore, selectConnectionState } from '@/stores/connectionStore';
import { ReconnectService } from '@/services/ssh/reconnect';
import type { Connection, ConnectionState } from '@/types/connection';
import type { ISSHClient } from '@/services/ssh/client';

/**
 * フックの戻り値
 */
export interface UseReconnectDialogResult {
  /** ダイアログ表示中かどうか */
  isVisible: boolean;
  /** 接続状態 */
  connectionState: ConnectionState;
  /** ダイアログを表示する */
  show: () => void;
  /** ダイアログを非表示にする */
  hide: () => void;
  /** 再接続を開始する */
  reconnect: (password?: string) => Promise<void>;
  /** 再接続をキャンセルする */
  cancel: () => void;
  /** 再試行する */
  retry: () => void;
}

/**
 * useReconnectDialog
 */
export function useReconnectDialog(
  connection: Connection,
  sshClient: ISSHClient
): UseReconnectDialogResult {
  const [isVisible, setIsVisible] = useState(false);
  const reconnectServiceRef = useRef<ReconnectService | null>(null);

  // ストアから接続状態を取得
  const connectionState = useConnectionStore((state) =>
    selectConnectionState(state, connection.id)
  );

  const {
    setReconnecting,
    recordReconnectAttempt,
    clearReconnectState,
    setConnectionState,
  } = useConnectionStore();

  // ReconnectServiceの初期化
  useEffect(() => {
    reconnectServiceRef.current = new ReconnectService(sshClient);

    // イベントハンドラを設定
    reconnectServiceRef.current.setEventHandlers(connection.id, {
      onAttemptStart: (attemptNumber, maxAttempts) => {
        setReconnecting(connection.id, attemptNumber, maxAttempts);
      },
      onAttemptFailed: (attemptNumber, error) => {
        recordReconnectAttempt(connection.id, {
          attemptNumber,
          result: 'failed',
          error,
        });
      },
      onSuccess: () => {
        setConnectionState(connection.id, { status: 'connected' });
        clearReconnectState(connection.id);
        // 成功後、少し待ってからダイアログを閉じる
        setTimeout(() => setIsVisible(false), 1000);
      },
      onGiveUp: (_totalAttempts, lastError) => {
        setConnectionState(connection.id, {
          status: 'error',
          error: lastError,
        });
      },
      onCancelled: () => {
        clearReconnectState(connection.id);
        setIsVisible(false);
      },
    });

    return () => {
      if (reconnectServiceRef.current) {
        reconnectServiceRef.current.removeEventHandlers(connection.id);
        reconnectServiceRef.current.cancelReconnect(connection.id);
      }
    };
  }, [
    connection.id,
    sshClient,
    setReconnecting,
    recordReconnectAttempt,
    setConnectionState,
    clearReconnectState,
  ]);

  // 切断検出時にダイアログを表示
  useEffect(() => {
    if (connectionState.status === 'disconnected' && connectionState.disconnectReason) {
      // ユーザー操作による切断でなければダイアログを表示
      if (connectionState.disconnectReason !== 'user_disconnect') {
        // 自動再接続が有効な場合は自動的に開始
        if (connection.autoReconnect) {
          reconnect();
        } else {
          setIsVisible(true);
        }
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connectionState.status, connectionState.disconnectReason, connection.autoReconnect]);

  const show = useCallback(() => {
    setIsVisible(true);
  }, []);

  const hide = useCallback(() => {
    setIsVisible(false);
  }, []);

  const reconnect = useCallback(
    async (password?: string) => {
      if (!reconnectServiceRef.current) return;

      setIsVisible(true);

      try {
        await reconnectServiceRef.current.startReconnect(connection, { password });
      } catch (error) {
        // エラーはイベントハンドラで処理される
        console.error('Reconnect failed:', error);
      }
    },
    [connection]
  );

  const cancel = useCallback(() => {
    if (reconnectServiceRef.current) {
      reconnectServiceRef.current.cancelReconnect(connection.id);
    }
    setIsVisible(false);
  }, [connection.id]);

  const retry = useCallback(() => {
    reconnect();
  }, [reconnect]);

  return {
    isVisible,
    connectionState,
    show,
    hide,
    reconnect,
    cancel,
    retry,
  };
}
