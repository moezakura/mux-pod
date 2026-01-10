/**
 * SSH Key Management Types
 *
 * SSH鍵管理機能で使用する型定義。
 * 実装先: src/types/sshKey.ts
 */

/**
 * SSH鍵メタデータ
 */
export interface SSHKey {
  /** UUID v4 */
  id: string;

  /** ユーザー定義の表示名 */
  name: string;

  /** 鍵タイプ */
  keyType: 'ed25519' | 'rsa-2048' | 'rsa-4096' | 'ecdsa';

  /** 公開鍵 (OpenSSH authorized_keys 形式) */
  publicKey: string;

  /** SHA256 フィンガープリント */
  fingerprint: string;

  /** 生体認証を要求するか */
  requireBiometrics: boolean;

  /** 作成日時 (Unix timestamp ms) */
  createdAt: number;

  /** インポートされた鍵かどうか */
  imported: boolean;
}

/**
 * SSH鍵の作成入力
 */
export type SSHKeyInput = Omit<SSHKey, 'id' | 'createdAt'>;

/**
 * 既知ホストエントリ
 */
export interface KnownHost {
  /** ホスト識別子 (host:port) */
  identifier: string;

  /** ホスト名 */
  host: string;

  /** ポート番号 */
  port: number;

  /** ホスト鍵タイプ */
  keyType: 'ssh-ed25519' | 'ssh-rsa' | 'ecdsa-sha2-nistp256' | 'ecdsa-sha2-nistp384';

  /** 公開鍵 (Base64) */
  publicKey: string;

  /** SHA256 フィンガープリント */
  fingerprint: string;

  /** 初回追加日時 (Unix timestamp ms) */
  addedAt: number;

  /** 最終検証成功日時 (Unix timestamp ms) */
  lastVerifiedAt: number;
}

/**
 * ホスト鍵検証結果
 */
export type HostKeyVerificationResult =
  | { status: 'trusted'; host: KnownHost }
  | { status: 'unknown'; fingerprint: string; keyType: KnownHost['keyType'] }
  | { status: 'changed'; previousFingerprint: string; newFingerprint: string };

/**
 * AsyncStorage保存キー
 */
export const SSH_KEYS_STORAGE_KEY = 'muxpod-ssh-keys';
export const KNOWN_HOSTS_STORAGE_KEY = 'muxpod-known-hosts';

/**
 * SecureStore鍵プレフィックス
 */
export const PRIVATE_KEY_PREFIX = 'muxpod-ssh-key-';
