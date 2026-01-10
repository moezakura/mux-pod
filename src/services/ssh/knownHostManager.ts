/**
 * Known Host Manager
 *
 * 既知ホストの管理を行うサービス。
 * MITM攻撃防止のためのホスト鍵検証機能を提供。
 */
import AsyncStorage from '@react-native-async-storage/async-storage';

import type {
  KnownHost,
  HostKeyType,
  HostKeyVerificationResult,
} from '@/types/sshKey';
import { KNOWN_HOSTS_STORAGE_KEY } from '@/types/sshKey';

/**
 * ホスト識別子を生成する
 */
function createHostIdentifier(host: string, port: number): string {
  return `${host}:${port}`;
}

/**
 * すべての既知ホストを取得する
 */
export async function getAllHosts(): Promise<KnownHost[]> {
  const data = await AsyncStorage.getItem(KNOWN_HOSTS_STORAGE_KEY);
  if (!data) {
    return [];
  }
  try {
    return JSON.parse(data) as KnownHost[];
  } catch {
    return [];
  }
}

/**
 * ホスト識別子で既知ホストを取得する
 */
export async function getHostByIdentifier(identifier: string): Promise<KnownHost | null> {
  const hosts = await getAllHosts();
  return hosts.find((h) => h.identifier === identifier) ?? null;
}

/**
 * ホスト名とポートで既知ホストを取得する
 */
export async function getHost(host: string, port: number): Promise<KnownHost | null> {
  const identifier = createHostIdentifier(host, port);
  return getHostByIdentifier(identifier);
}

/**
 * 既知ホストリストを保存する
 */
async function saveHosts(hosts: KnownHost[]): Promise<void> {
  await AsyncStorage.setItem(KNOWN_HOSTS_STORAGE_KEY, JSON.stringify(hosts));
}

/**
 * ホスト鍵を検証する
 *
 * @returns
 * - trusted: 既知のホストで鍵が一致
 * - unknown: 未知のホスト
 * - changed: 既知だが鍵が変更された（MITM攻撃の可能性）
 */
export async function verifyHostKey(
  host: string,
  port: number,
  keyType: HostKeyType,
  publicKey: string,
  fingerprint: string
): Promise<HostKeyVerificationResult> {
  const knownHost = await getHost(host, port);

  if (!knownHost) {
    // 未知のホスト
    return {
      status: 'unknown',
      fingerprint,
      keyType,
    };
  }

  if (knownHost.fingerprint === fingerprint) {
    // 既知のホストで鍵が一致
    // 最終検証日時を更新
    await updateHostLastVerified(knownHost.identifier);
    return {
      status: 'trusted',
      host: knownHost,
    };
  }

  // 鍵が変更された（危険！）
  return {
    status: 'changed',
    previousFingerprint: knownHost.fingerprint,
    newFingerprint: fingerprint,
  };
}

/**
 * 最終検証日時を更新する
 */
async function updateHostLastVerified(identifier: string): Promise<void> {
  const hosts = await getAllHosts();
  const index = hosts.findIndex((h) => h.identifier === identifier);
  if (index === -1) return;

  const existingHost = hosts[index]!;
  hosts[index] = {
    identifier: existingHost.identifier,
    host: existingHost.host,
    port: existingHost.port,
    keyType: existingHost.keyType,
    publicKey: existingHost.publicKey,
    fingerprint: existingHost.fingerprint,
    addedAt: existingHost.addedAt,
    lastVerifiedAt: Date.now(),
  };
  await saveHosts(hosts);
}

/**
 * 新しいホスト鍵を信頼済みとして保存する
 */
export async function trustHostKey(
  host: string,
  port: number,
  keyType: HostKeyType,
  publicKey: string,
  fingerprint: string
): Promise<KnownHost> {
  const identifier = createHostIdentifier(host, port);
  const timestamp = Date.now();

  const knownHost: KnownHost = {
    identifier,
    host,
    port,
    keyType,
    publicKey,
    fingerprint,
    addedAt: timestamp,
    lastVerifiedAt: timestamp,
  };

  const hosts = await getAllHosts();

  // 既存のエントリがあれば置換
  const existingIndex = hosts.findIndex((h) => h.identifier === identifier);
  if (existingIndex !== -1) {
    hosts[existingIndex] = knownHost;
  } else {
    hosts.push(knownHost);
  }

  await saveHosts(hosts);
  return knownHost;
}

/**
 * ホスト鍵を更新する（鍵変更時の確認後）
 */
export async function updateHostKey(
  identifier: string,
  keyType: HostKeyType,
  publicKey: string,
  fingerprint: string
): Promise<KnownHost | null> {
  const hosts = await getAllHosts();
  const index = hosts.findIndex((h) => h.identifier === identifier);

  if (index === -1) {
    return null;
  }

  const timestamp = Date.now();
  const existingHost = hosts[index]!;
  const updatedHost: KnownHost = {
    identifier: existingHost.identifier,
    host: existingHost.host,
    port: existingHost.port,
    keyType,
    publicKey,
    fingerprint,
    addedAt: existingHost.addedAt,
    lastVerifiedAt: timestamp,
  };

  hosts[index] = updatedHost;
  await saveHosts(hosts);
  return updatedHost;
}

/**
 * 既知ホストを削除する
 */
export async function deleteHost(identifier: string): Promise<boolean> {
  const hosts = await getAllHosts();
  const index = hosts.findIndex((h) => h.identifier === identifier);

  if (index === -1) {
    return false;
  }

  hosts.splice(index, 1);
  await saveHosts(hosts);
  return true;
}

/**
 * ホストを削除する（ホスト名とポートで指定）
 */
export async function deleteHostByAddress(host: string, port: number): Promise<boolean> {
  const identifier = createHostIdentifier(host, port);
  return deleteHost(identifier);
}

/**
 * すべての既知ホストを削除する
 */
export async function clearAllHosts(): Promise<void> {
  await AsyncStorage.removeItem(KNOWN_HOSTS_STORAGE_KEY);
}
