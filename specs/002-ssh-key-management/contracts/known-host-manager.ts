/**
 * Known Host Manager Service Contract
 *
 * 既知ホストの管理と検証を行うサービスのインターフェース定義。
 * 実装: src/services/ssh/knownHostManager.ts
 */

import type { KnownHost, HostKeyVerificationResult } from './types';

/**
 * ホスト鍵情報
 */
export interface HostKeyInfo {
  /** ホスト名 */
  host: string;
  /** ポート番号 */
  port: number;
  /** 鍵タイプ */
  keyType: KnownHost['keyType'];
  /** 公開鍵 (Base64) */
  publicKey: string;
  /** フィンガープリント */
  fingerprint: string;
}

/**
 * Known Host Manager インターフェース
 */
export interface KnownHostManagerService {
  /**
   * ホスト鍵を検証する
   * @param hostKeyInfo サーバーから受信したホスト鍵情報
   * @returns 検証結果
   */
  verifyHostKey(hostKeyInfo: HostKeyInfo): Promise<HostKeyVerificationResult>;

  /**
   * ホスト鍵を信頼済みとして保存する
   * @param hostKeyInfo ホスト鍵情報
   */
  trustHostKey(hostKeyInfo: HostKeyInfo): Promise<KnownHost>;

  /**
   * ホスト鍵を更新する（鍵変更時）
   * @param hostKeyInfo 新しいホスト鍵情報
   */
  updateHostKey(hostKeyInfo: HostKeyInfo): Promise<KnownHost>;

  /**
   * すべての既知ホストを取得する
   */
  getAllHosts(): Promise<KnownHost[]>;

  /**
   * 識別子でホストを取得する
   * @param identifier host:port 形式
   */
  getHostByIdentifier(identifier: string): Promise<KnownHost | null>;

  /**
   * ホストエントリを削除する
   * @param identifier host:port 形式
   * @returns 削除成功時 true
   */
  deleteHost(identifier: string): Promise<boolean>;

  /**
   * すべての既知ホストを削除する
   */
  clearAllHosts(): Promise<void>;

  /**
   * ホスト識別子を生成する
   */
  createIdentifier(host: string, port: number): string;
}
