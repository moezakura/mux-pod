/**
 * SSH接続設定
 *
 * AsyncStorageに永続化される接続情報を表す。
 */
export interface Connection {
  /** UUID v4 */
  id: string;
  /** 表示名 (e.g., "Production Server") */
  name: string;
  /** ホスト名 or IPアドレス */
  host: string;
  /** SSHポート (default: 22) */
  port: number;
  /** SSHユーザー名 */
  username: string;
  /** 認証方式 */
  authMethod: 'password' | 'key';
  /** SSH鍵ID (key認証時) */
  keyId?: string;
  /** 接続タイムアウト秒 (default: 30) */
  timeout: number;
  /** Keepalive間隔秒 (default: 60, 0 = 無効) */
  keepAliveInterval: number;

  // 再接続設定
  /** 自動再接続有効フラグ (default: true) */
  autoReconnect: boolean;
  /** 最大試行回数 (default: 3) */
  maxReconnectAttempts: number;
  /** 試行間隔(ms) (default: 5000) */
  reconnectInterval: number;

  // メタ情報
  /** カスタムアイコン名 */
  icon?: string;
  /** カード色 (#RRGGBB) */
  color?: string;
  /** タグ */
  tags?: string[];
  /** 最終接続日時 (Unix timestamp ms) */
  lastConnected?: number;
  /** 作成日時 (Unix timestamp ms) */
  createdAt: number;
  /** 更新日時 (Unix timestamp ms) */
  updatedAt: number;
}

/**
 * 接続の作成に必要な情報
 */
export type ConnectionInput = Omit<Connection, 'id' | 'createdAt' | 'updatedAt'>;

/**
 * 接続状態
 */
export type ConnectionStatus =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'error';

/**
 * 切断理由
 */
export type DisconnectReason =
  | 'network_error'      // ネットワーク障害
  | 'server_closed'      // サーバー側で切断
  | 'auth_failed'        // 認証失敗
  | 'timeout'            // タイムアウト
  | 'user_disconnect'    // ユーザー操作による切断
  | 'unknown';           // 不明

/**
 * 再接続試行の結果
 */
export interface AttemptResult {
  /** 試行番号 */
  attemptNumber: number;
  /** 試行時刻 (Unix timestamp ms) */
  attemptedAt: number;
  /** 結果 */
  result: 'success' | 'failed' | 'cancelled';
  /** 失敗理由 (result === 'failed' の場合) */
  error?: string;
}

/**
 * 再接続試行の状態
 *
 * 永続化されない、現在の再接続試行を追跡する。
 */
export interface ReconnectAttempt {
  /** 試行開始時刻 (Unix timestamp ms) */
  startedAt: number;
  /** 現在の試行回数 (1から開始) */
  attemptNumber: number;
  /** 最大試行回数 (Connection.maxReconnectAttemptsからコピー) */
  maxAttempts: number;
  /** 次回試行予定時刻 (Unix timestamp ms, 待機中のみ) */
  nextAttemptAt?: number;
  /** 各試行の結果履歴 */
  history: AttemptResult[];
}

/**
 * 接続のランタイム状態
 *
 * 永続化されない、現在の接続状態を表す。
 */
export interface ConnectionState {
  /** 接続ID */
  connectionId: string;
  /** 接続状態 */
  status: ConnectionStatus;
  /** エラーメッセージ */
  error?: string;
  /** RTT (ms) */
  latency?: number;
  /** 接続開始日時 (Unix timestamp ms) */
  connectedAt?: number;
  /** 切断時刻 (Unix timestamp ms) */
  disconnectedAt?: number;
  /** 切断理由 */
  disconnectReason?: DisconnectReason;
  /** 現在の再接続試行情報 */
  reconnectAttempt?: ReconnectAttempt;
}

/**
 * デフォルト再接続設定
 */
export const DEFAULT_RECONNECT_SETTINGS = {
  autoReconnect: true,
  maxReconnectAttempts: 3,
  reconnectInterval: 5000,  // 5秒
} as const;

/**
 * デフォルト接続設定
 */
export const DEFAULT_CONNECTION: Partial<Connection> = {
  port: 22,
  timeout: 30,
  keepAliveInterval: 60,
  authMethod: 'password',
  ...DEFAULT_RECONNECT_SETTINGS,
};

/**
 * AsyncStorageの保存キー
 */
export const CONNECTIONS_STORAGE_KEY = 'muxpod-connections';
