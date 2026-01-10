/**
 * ReconnectService Contract
 *
 * SSH再接続ロジックを管理するサービスのインターフェース定義。
 * 実装は src/services/ssh/reconnect.ts に配置する。
 */

import type { Connection, ConnectionState } from '@/types/connection';

/**
 * 再接続オプション
 */
export interface ReconnectOptions {
  /** 認証情報（パスワードまたは秘密鍵） */
  password?: string;
  privateKey?: string;
  passphrase?: string;
}

/**
 * 再接続結果
 */
export interface ReconnectResult {
  /** 成功したかどうか */
  success: boolean;
  /** 試行回数 */
  attemptCount: number;
  /** エラーメッセージ（失敗時） */
  error?: string;
  /** キャンセルされたかどうか */
  cancelled?: boolean;
}

/**
 * 再接続イベント
 */
export interface ReconnectEvents {
  /** 再接続試行開始時 */
  onAttemptStart: (attemptNumber: number, maxAttempts: number) => void;
  /** 再接続試行失敗時 */
  onAttemptFailed: (attemptNumber: number, error: string) => void;
  /** 再接続成功時 */
  onSuccess: () => void;
  /** 再接続断念時（最大試行回数到達） */
  onGiveUp: (totalAttempts: number, lastError: string) => void;
  /** 再接続キャンセル時 */
  onCancelled: () => void;
}

/**
 * ReconnectService インターフェース
 */
export interface IReconnectService {
  /**
   * 切断を処理し、設定に応じて自動再接続を開始するか判断する
   * @param connection 切断された接続
   * @param state 現在の接続状態
   * @returns 自動再接続が開始された場合はtrue
   */
  handleDisconnection(connection: Connection, state: ConnectionState): boolean;

  /**
   * 再接続を開始する
   * @param connection 再接続する接続
   * @param options 認証情報などのオプション
   * @returns 再接続結果のPromise
   */
  startReconnect(connection: Connection, options?: ReconnectOptions): Promise<ReconnectResult>;

  /**
   * 進行中の再接続をキャンセルする
   * @param connectionId 接続ID
   */
  cancelReconnect(connectionId: string): void;

  /**
   * 再接続が進行中かどうかを確認する
   * @param connectionId 接続ID
   */
  isReconnecting(connectionId: string): boolean;

  /**
   * イベントハンドラを設定する
   * @param connectionId 接続ID
   * @param events イベントハンドラ
   */
  setEventHandlers(connectionId: string, events: Partial<ReconnectEvents>): void;

  /**
   * イベントハンドラを解除する
   * @param connectionId 接続ID
   */
  removeEventHandlers(connectionId: string): void;
}
