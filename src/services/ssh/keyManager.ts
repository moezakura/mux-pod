/**
 * SSH Key Manager
 *
 * SSH鍵の生成、インポート、管理を行うサービス。
 * 秘密鍵はSecureStoreに保存され、メタデータはAsyncStorageに保存される。
 */
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';
import * as LocalAuthentication from 'expo-local-authentication';
// Note: react-native-ssh-sftp will be used for actual key generation in production
// import SSHClient from 'react-native-ssh-sftp';

import type { SSHKey, SSHKeyType } from '@/types/sshKey';
import { SSH_KEYS_STORAGE_KEY, PRIVATE_KEY_PREFIX } from '@/types/sshKey';

/**
 * 鍵生成オプション
 */
export interface GenerateKeyOptions {
  /** 鍵の表示名 */
  name: string;
  /** 鍵タイプ (デフォルト: ed25519) */
  keyType?: SSHKeyType;
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
 * 鍵インポートオプション
 */
export interface ImportKeyOptions {
  /** 鍵の表示名 */
  name: string;
  /** 秘密鍵 (PEM/OpenSSH形式) */
  privateKey: string;
  /** パスフレーズ (暗号化されている場合) */
  passphrase?: string;
  /** 生体認証を要求するか (デフォルト: true) */
  requireBiometrics?: boolean;
}

/**
 * 鍵インポート結果
 */
export interface ImportKeyResult {
  /** インポートされた鍵のメタデータ */
  key: SSHKey;
  /** 公開鍵 (authorized_keys 形式) */
  publicKey: string;
}

/**
 * UUIDを生成する
 */
function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * SHA256フィンガープリントを計算する（簡易版）
 */
function calculateFingerprint(publicKey: string): string {
  // 実際のフィンガープリント計算はreact-native-ssh-sftpに依存
  // ここでは公開鍵からハッシュを生成する簡易実装
  let hash = 0;
  for (let i = 0; i < publicKey.length; i++) {
    const char = publicKey.charCodeAt(i);
    hash = ((hash << 5) - hash + char) | 0;
  }
  const hashStr = Math.abs(hash).toString(16).padStart(8, '0');
  return `SHA256:${hashStr}${hashStr}${hashStr}${hashStr}`;
}

/**
 * すべての鍵メタデータを取得する
 */
export async function getAllKeys(): Promise<SSHKey[]> {
  const data = await AsyncStorage.getItem(SSH_KEYS_STORAGE_KEY);
  if (!data) {
    return [];
  }
  try {
    return JSON.parse(data) as SSHKey[];
  } catch {
    return [];
  }
}

/**
 * IDで鍵を取得する
 */
export async function getKeyById(id: string): Promise<SSHKey | null> {
  const keys = await getAllKeys();
  return keys.find((k) => k.id === id) ?? null;
}

/**
 * 鍵名の重複チェック
 */
export async function isNameAvailable(name: string): Promise<boolean> {
  const keys = await getAllKeys();
  return !keys.some((k) => k.name === name);
}

/**
 * 鍵メタデータを保存する
 */
async function saveKeyMetadata(keys: SSHKey[]): Promise<void> {
  await AsyncStorage.setItem(SSH_KEYS_STORAGE_KEY, JSON.stringify(keys));
}

/**
 * 秘密鍵をSecureStoreに保存する
 */
async function savePrivateKey(id: string, privateKey: string): Promise<void> {
  const key = `${PRIVATE_KEY_PREFIX}${id}`;
  await SecureStore.setItemAsync(key, privateKey);
}

/**
 * 秘密鍵をSecureStoreから削除する
 */
async function deletePrivateKeyFromStore(id: string): Promise<void> {
  const key = `${PRIVATE_KEY_PREFIX}${id}`;
  await SecureStore.deleteItemAsync(key);
}

/**
 * 生体認証を実行する
 */
async function authenticateBiometric(): Promise<boolean> {
  const result = await LocalAuthentication.authenticateAsync({
    promptMessage: 'SSH鍵へのアクセスを許可',
    cancelLabel: 'キャンセル',
    disableDeviceFallback: false,
  });
  return result.success;
}

/**
 * 新しいSSH鍵ペアを生成する
 */
export async function generateKey(options: GenerateKeyOptions): Promise<GenerateKeyResult> {
  const { name, keyType = 'ed25519', requireBiometrics = true } = options;

  // 名前の重複チェック
  if (!(await isNameAvailable(name))) {
    throw new Error('Key name already exists');
  }

  // 名前のバリデーション
  if (!name || name.trim().length === 0) {
    throw new Error('Key name cannot be empty');
  }
  if (name.length > 50) {
    throw new Error('Key name must be 50 characters or less');
  }

  // ED25519鍵ペアを生成
  // react-native-ssh-sftpを使用して鍵を生成
  // 注: 実際の実装ではライブラリの鍵生成機能を使用
  const id = generateUUID();
  const timestamp = Date.now();

  // モック用の鍵データ（実際の実装ではネイティブモジュールで生成）
  const privateKey = `-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxAAAAsHxxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-----END OPENSSH PRIVATE KEY-----`;

  const publicKey = `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx muxpod-${name.replace(/\s+/g, '-').toLowerCase()}`;

  const fingerprint = calculateFingerprint(publicKey);

  // 秘密鍵をSecureStoreに保存
  await savePrivateKey(id, privateKey);

  // メタデータを作成
  const keyMetadata: SSHKey = {
    id,
    name,
    keyType,
    publicKey,
    fingerprint,
    requireBiometrics,
    createdAt: timestamp,
    imported: false,
  };

  // 既存の鍵リストに追加
  const keys = await getAllKeys();
  keys.push(keyMetadata);
  await saveKeyMetadata(keys);

  return {
    key: keyMetadata,
    publicKey,
  };
}

/**
 * 秘密鍵を取得する（生体認証が必要な場合あり）
 */
export async function getPrivateKey(id: string): Promise<string> {
  const key = await getKeyById(id);
  if (!key) {
    throw new Error('Key not found');
  }

  // 生体認証が必要な場合
  if (key.requireBiometrics) {
    const authenticated = await authenticateBiometric();
    if (!authenticated) {
      throw new Error('Biometric authentication failed');
    }
  }

  const storageKey = `${PRIVATE_KEY_PREFIX}${id}`;
  const privateKey = await SecureStore.getItemAsync(storageKey);
  if (!privateKey) {
    throw new Error('Private key not found in secure storage');
  }

  return privateKey;
}

/**
 * 鍵を削除する
 */
export async function deleteKey(id: string): Promise<boolean> {
  const keys = await getAllKeys();
  const index = keys.findIndex((k) => k.id === id);

  if (index === -1) {
    return false;
  }

  // SecureStoreから秘密鍵を削除
  await deletePrivateKeyFromStore(id);

  // メタデータから削除
  keys.splice(index, 1);
  await saveKeyMetadata(keys);

  return true;
}

/**
 * 秘密鍵の形式を検証する
 */
export function validatePrivateKey(privateKey: string): {
  valid: boolean;
  keyType?: SSHKeyType;
  encrypted?: boolean;
  error?: string;
} {
  if (!privateKey || privateKey.trim().length === 0) {
    return { valid: false, error: 'Private key is empty' };
  }

  // PEM形式のチェック
  const pemPattern =
    /-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----[\s\S]+-----END (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----/;

  if (!pemPattern.test(privateKey)) {
    return { valid: false, error: 'Invalid private key format' };
  }

  // 鍵タイプの判定
  let keyType: SSHKeyType = 'ed25519';
  if (privateKey.includes('BEGIN RSA PRIVATE KEY') || privateKey.includes('BEGIN PRIVATE KEY')) {
    // RSA鍵の場合、サイズを判定する必要があるが、ここでは2048と仮定
    keyType = 'rsa-2048';
  } else if (privateKey.includes('BEGIN EC PRIVATE KEY')) {
    keyType = 'ecdsa';
  } else if (privateKey.includes('BEGIN OPENSSH PRIVATE KEY')) {
    keyType = 'ed25519';
  }

  // 暗号化チェック（簡易版）
  const encrypted =
    privateKey.includes('ENCRYPTED') ||
    privateKey.includes('Proc-Type: 4,ENCRYPTED');

  return { valid: true, keyType, encrypted };
}

/**
 * 秘密鍵から公開鍵を抽出する（簡易版）
 *
 * 注: 実際の実装ではreact-native-ssh-sftpを使用する
 */
function extractPublicKeyFromPrivate(privateKey: string, keyType: SSHKeyType, name: string): string {
  // 実際の実装ではネイティブモジュールで公開鍵を抽出
  // ここではモックの公開鍵を返す
  const keyTypePrefix = keyType === 'ed25519' ? 'ssh-ed25519' :
                        keyType === 'ecdsa' ? 'ecdsa-sha2-nistp256' :
                        'ssh-rsa';
  const comment = `muxpod-${name.replace(/\s+/g, '-').toLowerCase()}`;
  return `${keyTypePrefix} AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx ${comment}`;
}

/**
 * パスフレーズ付き秘密鍵を復号する
 *
 * 注: 実際の実装ではreact-native-ssh-sftpを使用する
 */
function decryptPrivateKey(privateKey: string, _passphrase: string): string {
  // 実際の実装ではネイティブモジュールで復号
  // ここでは秘密鍵をそのまま返す（モック）
  return privateKey;
}

/**
 * 既存のSSH鍵をインポートする
 */
export async function importKey(options: ImportKeyOptions): Promise<ImportKeyResult> {
  const { name, privateKey, passphrase, requireBiometrics = true } = options;

  // 名前のバリデーション
  if (!name || name.trim().length === 0) {
    throw new Error('Key name cannot be empty');
  }
  if (name.length > 50) {
    throw new Error('Key name must be 50 characters or less');
  }

  // 名前の重複チェック
  if (!(await isNameAvailable(name))) {
    throw new Error('Key name already exists');
  }

  // 秘密鍵のバリデーション
  const validation = validatePrivateKey(privateKey);
  if (!validation.valid) {
    throw new Error(validation.error ?? 'Invalid private key');
  }

  // 暗号化されている場合は復号
  let decryptedKey = privateKey;
  if (validation.encrypted) {
    if (!passphrase) {
      throw new Error('Passphrase required for encrypted key');
    }
    try {
      decryptedKey = decryptPrivateKey(privateKey, passphrase);
    } catch {
      throw new Error('Failed to decrypt private key');
    }
  }

  const id = generateUUID();
  const timestamp = Date.now();
  const keyType = validation.keyType ?? 'ed25519';

  // 公開鍵を抽出
  const publicKey = extractPublicKeyFromPrivate(decryptedKey, keyType, name);
  const fingerprint = calculateFingerprint(publicKey);

  // 秘密鍵をSecureStoreに保存
  await savePrivateKey(id, decryptedKey);

  // メタデータを作成
  const keyMetadata: SSHKey = {
    id,
    name,
    keyType,
    publicKey,
    fingerprint,
    requireBiometrics,
    createdAt: timestamp,
    imported: true,
  };

  // 既存の鍵リストに追加
  const keys = await getAllKeys();
  keys.push(keyMetadata);
  await saveKeyMetadata(keys);

  return {
    key: keyMetadata,
    publicKey,
  };
}
