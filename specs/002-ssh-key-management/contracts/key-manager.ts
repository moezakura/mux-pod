/**
 * SSH Key Manager Service Contract
 *
 * SSH鍵の生成、インポート、管理を行うサービスのインターフェース定義。
 * 実装: src/services/ssh/keyManager.ts
 */

import type { SSHKey } from './types';

/**
 * 鍵生成オプション
 */
export interface GenerateKeyOptions {
  /** 鍵の表示名 */
  name: string;
  /** 鍵タイプ (デフォルト: ed25519) */
  keyType?: 'ed25519' | 'rsa-2048' | 'rsa-4096';
  /** 生体認証を要求するか (デフォルト: true) */
  requireBiometrics?: boolean;
}

/**
 * 鍵インポートオプション
 */
export interface ImportKeyOptions {
  /** 鍵の表示名 */
  name: string;
  /** 秘密鍵 (PEM または OpenSSH 形式) */
  privateKey: string;
  /** パスフレーズ (暗号化されている場合) */
  passphrase?: string;
  /** 生体認証を要求するか (デフォルト: true) */
  requireBiometrics?: boolean;
}

/**
 * 鍵生成結果
 */
export interface GenerateKeyResult {
  /** 生成された鍵のメタデータ */
  key: SSHKey;
  /** 公開鍵 (authorized_keys 形式) */
  publicKey: string;
}

/**
 * 鍵インポートエラー
 */
export type ImportKeyError =
  | { type: 'INVALID_FORMAT'; message: string }
  | { type: 'INVALID_PASSPHRASE'; message: string }
  | { type: 'UNSUPPORTED_KEY_TYPE'; message: string }
  | { type: 'DUPLICATE_NAME'; message: string }
  | { type: 'STORAGE_ERROR'; message: string };

/**
 * SSH Key Manager インターフェース
 */
export interface KeyManagerService {
  /**
   * 新しいSSH鍵ペアを生成する
   * @throws 生成失敗時
   */
  generateKey(options: GenerateKeyOptions): Promise<GenerateKeyResult>;

  /**
   * 既存の秘密鍵をインポートする
   * @throws ImportKeyError
   */
  importKey(options: ImportKeyOptions): Promise<SSHKey>;

  /**
   * すべての鍵メタデータを取得する
   */
  getAllKeys(): Promise<SSHKey[]>;

  /**
   * IDで鍵を取得する
   */
  getKeyById(id: string): Promise<SSHKey | null>;

  /**
   * 秘密鍵を取得する（生体認証が必要な場合あり）
   * @throws 認証失敗時
   */
  getPrivateKey(id: string): Promise<string>;

  /**
   * 鍵を削除する
   * @returns 削除成功時 true
   */
  deleteKey(id: string): Promise<boolean>;

  /**
   * 鍵名の重複チェック
   */
  isNameAvailable(name: string): Promise<boolean>;

  /**
   * 秘密鍵の形式を検証する
   */
  validatePrivateKey(privateKey: string): {
    valid: boolean;
    keyType?: SSHKey['keyType'];
    encrypted?: boolean;
    error?: string;
  };
}
