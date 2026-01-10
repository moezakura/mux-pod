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
 * 接続のランタイム状態
 *
 * 永続化されない、現在の接続状態を表す。
 */
export interface ConnectionState {
  /** 接続ID */
  connectionId: string;
  /** 接続状態 */
  status: 'disconnected' | 'connecting' | 'connected' | 'error';
  /** エラーメッセージ */
  error?: string;
  /** RTT (ms) */
  latency?: number;
  /** 接続開始日時 (Unix timestamp ms) */
  connectedAt?: number;
}

/**
 * デフォルト接続設定
 */
export const DEFAULT_CONNECTION: Partial<Connection> = {
  port: 22,
  timeout: 30,
  keepAliveInterval: 60,
  authMethod: 'password',
};

/**
 * AsyncStorageの保存キー
 */
export const CONNECTIONS_STORAGE_KEY = 'muxpod-connections';
