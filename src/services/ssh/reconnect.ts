/**
 * ReconnectService
 *
 * SSH再接続ロジックを管理するサービス。
 */
import type { Connection, ConnectionState, DisconnectReason } from '@/types/connection';

/**
 * 再接続オプション
 */
export interface ReconnectOptions {
  /** パスワード */
  password?: string;
  /** 秘密鍵 */
  privateKey?: string;
  /** パスフレーズ */
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
  /** エラーメッセージ */
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
  /** 再接続断念時 */
  onGiveUp: (totalAttempts: number, lastError: string) => void;
  /** 再接続キャンセル時 */
  onCancelled: () => void;
}

/**
 * SSHクライアントインターフェース
 */
interface ISSHClient {
  connect: (connection: Connection, options: ReconnectOptions) => Promise<void>;
  disconnect: () => Promise<void>;
  isConnected: () => boolean;
}

/**
 * 再接続状態
 */
interface ReconnectState {
  /** キャンセルフラグ */
  cancelled: boolean;
  /** タイマーID */
  timerId?: ReturnType<typeof setTimeout>;
  /** 現在の試行回数 */
  currentAttempt: number;
  /** wait解除用のresolve関数 */
  waitResolve?: () => void;
}

/**
 * 自動再接続を行わない切断理由
 */
const NON_RETRYABLE_REASONS: DisconnectReason[] = ['user_disconnect', 'auth_failed'];

/**
 * ReconnectService
 */
export class ReconnectService {
  private sshClient: ISSHClient;
  private reconnectStates: Map<string, ReconnectState> = new Map();
  private eventHandlers: Map<string, Partial<ReconnectEvents>> = new Map();

  constructor(sshClient: ISSHClient) {
    this.sshClient = sshClient;
  }

  /**
   * 切断を処理し、自動再接続を開始するか判断する
   */
  handleDisconnection(connection: Connection, state: ConnectionState): boolean {
    // 自動再接続が無効な場合
    if (!connection.autoReconnect) {
      return false;
    }

    // リトライ不可能な切断理由の場合
    if (state.disconnectReason && NON_RETRYABLE_REASONS.includes(state.disconnectReason)) {
      return false;
    }

    return true;
  }

  /**
   * 再接続を開始する
   */
  async startReconnect(
    connection: Connection,
    options?: ReconnectOptions
  ): Promise<ReconnectResult> {
    const { id, maxReconnectAttempts, reconnectInterval } = connection;

    // 再接続状態を初期化
    const state: ReconnectState = {
      cancelled: false,
      currentAttempt: 0,
    };
    this.reconnectStates.set(id, state);

    let lastError = '';

    try {
      while (state.currentAttempt < maxReconnectAttempts && !state.cancelled) {
        state.currentAttempt++;

        // 試行開始イベント
        this.fireEvent(id, 'onAttemptStart', state.currentAttempt, maxReconnectAttempts);

        try {
          await this.sshClient.connect(connection, options || {});

          // 成功
          this.fireEvent(id, 'onSuccess');
          this.reconnectStates.delete(id);

          return {
            success: true,
            attemptCount: state.currentAttempt,
          };
        } catch (error) {
          lastError = error instanceof Error ? error.message : String(error);
          this.fireEvent(id, 'onAttemptFailed', state.currentAttempt, lastError);

          // キャンセルされた場合は中断
          if (state.cancelled) {
            break;
          }

          // 最後の試行でなければ待機
          if (state.currentAttempt < maxReconnectAttempts) {
            await this.wait(reconnectInterval, id);
          }
        }
      }

      // キャンセルされた場合
      if (state.cancelled) {
        this.fireEvent(id, 'onCancelled');
        this.reconnectStates.delete(id);

        return {
          success: false,
          attemptCount: state.currentAttempt,
          cancelled: true,
        };
      }

      // 最大試行回数到達
      this.fireEvent(id, 'onGiveUp', state.currentAttempt, lastError);
      this.reconnectStates.delete(id);

      return {
        success: false,
        attemptCount: state.currentAttempt,
        error: lastError,
      };
    } finally {
      this.reconnectStates.delete(id);
    }
  }

  /**
   * 再接続をキャンセルする
   */
  cancelReconnect(connectionId: string): void {
    const state = this.reconnectStates.get(connectionId);
    if (state) {
      state.cancelled = true;
      if (state.timerId) {
        clearTimeout(state.timerId);
      }
      // wait中のPromiseを解除
      if (state.waitResolve) {
        state.waitResolve();
      }
    }
  }

  /**
   * 再接続中かどうかを確認する
   */
  isReconnecting(connectionId: string): boolean {
    return this.reconnectStates.has(connectionId);
  }

  /**
   * イベントハンドラを設定する
   */
  setEventHandlers(connectionId: string, events: Partial<ReconnectEvents>): void {
    this.eventHandlers.set(connectionId, events);
  }

  /**
   * イベントハンドラを解除する
   */
  removeEventHandlers(connectionId: string): void {
    this.eventHandlers.delete(connectionId);
  }

  /**
   * イベントを発火する
   */
  private fireEvent<K extends keyof ReconnectEvents>(
    connectionId: string,
    event: K,
    ...args: Parameters<ReconnectEvents[K]>
  ): void {
    const handlers = this.eventHandlers.get(connectionId);
    const handler = handlers?.[event];
    if (handler) {
      // @ts-expect-error - TypeScript can't infer the correct parameter types here
      handler(...args);
    }
  }

  /**
   * 指定時間待機する（キャンセル可能）
   */
  private wait(ms: number, connectionId: string): Promise<void> {
    return new Promise((resolve) => {
      const state = this.reconnectStates.get(connectionId);
      if (state) {
        state.waitResolve = resolve;
        state.timerId = setTimeout(() => {
          state.waitResolve = undefined;
          resolve();
        }, ms);
      } else {
        resolve();
      }
    });
  }
}

/**
 * ReconnectServiceを作成する
 */
export function createReconnectService(sshClient: ISSHClient): ReconnectService {
  return new ReconnectService(sshClient);
}
