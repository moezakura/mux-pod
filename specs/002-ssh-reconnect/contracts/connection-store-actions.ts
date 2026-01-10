/**
 * ConnectionStore Actions Contract
 *
 * connectionStoreに追加する再接続関連アクションの定義。
 * 実装は src/stores/connectionStore.ts に追加する。
 */

import type { Connection, ConnectionState } from '@/types/connection';

/**
 * 再接続関連のアクション（既存のConnectionStoreActionsに追加）
 */
export interface ReconnectStoreActions {
  /**
   * 接続の再接続設定を更新する
   * @param id 接続ID
   * @param settings 再接続設定
   */
  updateReconnectSettings: (
    id: string,
    settings: Partial<{
      autoReconnect: boolean;
      maxReconnectAttempts: number;
      reconnectInterval: number;
    }>
  ) => void;

  /**
   * 切断状態に更新する（理由と時刻を記録）
   * @param id 接続ID
   * @param reason 切断理由
   */
  setDisconnected: (
    id: string,
    reason: 'network_error' | 'server_closed' | 'auth_failed' | 'timeout' | 'user_disconnect' | 'unknown'
  ) => void;

  /**
   * 再接続中状態に更新する
   * @param id 接続ID
   * @param attemptNumber 現在の試行番号
   * @param maxAttempts 最大試行回数
   */
  setReconnecting: (id: string, attemptNumber: number, maxAttempts: number) => void;

  /**
   * 再接続試行結果を記録する
   * @param id 接続ID
   * @param result 試行結果
   */
  recordReconnectAttempt: (
    id: string,
    result: {
      attemptNumber: number;
      result: 'success' | 'failed' | 'cancelled';
      error?: string;
    }
  ) => void;

  /**
   * 再接続状態をクリアする（成功・断念・キャンセル時）
   * @param id 接続ID
   */
  clearReconnectState: (id: string) => void;
}

/**
 * 拡張されたセレクター
 */
export interface ReconnectSelectors {
  /**
   * 自動再接続が有効かどうかを取得
   * @param connectionId 接続ID
   */
  selectAutoReconnect: (connectionId: string) => boolean;

  /**
   * 再接続試行情報を取得
   * @param connectionId 接続ID
   */
  selectReconnectAttempt: (connectionId: string) => {
    current: number;
    max: number;
    nextAttemptAt?: number;
  } | null;

  /**
   * 切断理由を取得
   * @param connectionId 接続ID
   */
  selectDisconnectReason: (connectionId: string) => string | null;
}

/**
 * 期待される動作
 *
 * 1. setDisconnected: status='disconnected', disconnectedAt=now, disconnectReason=reason
 * 2. setReconnecting: status='reconnecting', reconnectAttempt を初期化
 * 3. recordReconnectAttempt: reconnectAttempt.history に追加
 * 4. clearReconnectState: status を維持したまま reconnectAttempt をクリア
 * 5. 全ての更新は connectionStates の該当エントリを更新
 */
