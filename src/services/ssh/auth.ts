/**
 * SSH認証ヘルパー
 *
 * パスワードの安全な保存・読み込みと認証オプションのバリデーション。
 */
import * as SecureStore from 'expo-secure-store';
import type { SSHConnectOptions } from './client';

/**
 * SecureStoreのキープレフィックス
 */
export const PASSWORD_KEY_PREFIX = 'muxpod-ssh-password-';

/**
 * パスワードをSecureStoreに保存する
 * @param connectionId 接続ID
 * @param password パスワード
 */
export async function savePassword(connectionId: string, password: string): Promise<void> {
  if (!password) {
    throw new Error('Password cannot be empty');
  }

  const key = `${PASSWORD_KEY_PREFIX}${connectionId}`;
  await SecureStore.setItemAsync(key, password);
}

/**
 * パスワードをSecureStoreから読み込む
 * @param connectionId 接続ID
 * @returns パスワード（見つからない場合はnull）
 */
export async function loadPassword(connectionId: string): Promise<string | null> {
  const key = `${PASSWORD_KEY_PREFIX}${connectionId}`;
  return await SecureStore.getItemAsync(key);
}

/**
 * パスワードをSecureStoreから削除する
 * @param connectionId 接続ID
 */
export async function deletePassword(connectionId: string): Promise<void> {
  const key = `${PASSWORD_KEY_PREFIX}${connectionId}`;
  await SecureStore.deleteItemAsync(key);
}

/**
 * 認証オプションをバリデートする
 * @param authMethod 認証方式
 * @param options 認証オプション
 * @throws 認証情報が不足している場合
 */
export function validateAuthOptions(
  authMethod: 'password' | 'key',
  options: SSHConnectOptions
): void {
  if (authMethod === 'password') {
    if (!options.password || options.password.trim() === '') {
      throw new Error('Password is required for password authentication');
    }
  } else if (authMethod === 'key') {
    if (!options.privateKey || options.privateKey.trim() === '') {
      throw new Error('Private key is required for key authentication');
    }
  }
}

/**
 * 秘密鍵の形式を検証する
 * @param privateKey 秘密鍵（PEM形式）
 * @returns 有効な場合はtrue
 */
export function isValidPrivateKey(privateKey: string): boolean {
  // PEM形式のチェック（簡易版）
  const pemPattern =
    /-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----[\s\S]+-----END (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----/;
  return pemPattern.test(privateKey);
}

/**
 * 秘密鍵のタイプを判定する
 * @param privateKey 秘密鍵（PEM形式）
 * @returns 鍵タイプ
 */
export function getKeyType(privateKey: string): 'rsa' | 'ed25519' | 'ecdsa' | 'dsa' | 'unknown' {
  if (privateKey.includes('BEGIN RSA PRIVATE KEY') || privateKey.includes('BEGIN PRIVATE KEY')) {
    return 'rsa';
  }
  if (privateKey.includes('BEGIN OPENSSH PRIVATE KEY')) {
    // OpenSSH形式はED25519の可能性が高い
    return 'ed25519';
  }
  if (privateKey.includes('BEGIN EC PRIVATE KEY')) {
    return 'ecdsa';
  }
  if (privateKey.includes('BEGIN DSA PRIVATE KEY')) {
    return 'dsa';
  }
  return 'unknown';
}
