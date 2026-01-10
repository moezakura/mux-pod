/**
 * ReconnectDialog Contract
 *
 * 再接続確認ダイアログのインターフェース定義。
 * 実装は src/components/connection/ReconnectDialog.tsx に配置する。
 */

import type { Connection, ConnectionState } from '@/types/connection';

/**
 * ダイアログの状態
 */
export type DialogState =
  | 'confirm'      // 再接続確認待ち
  | 'connecting'   // 接続試行中
  | 'password'     // パスワード入力待ち
  | 'error'        // エラー表示
  | 'success';     // 成功（自動閉じる前）

/**
 * ReconnectDialogのProps
 */
export interface ReconnectDialogProps {
  /** 表示するかどうか */
  visible: boolean;

  /** 再接続対象の接続 */
  connection: Connection;

  /** 接続状態 */
  connectionState: ConnectionState;

  /** 再接続ボタン押下時 */
  onReconnect: (password?: string) => void;

  /** キャンセルボタン押下時 */
  onCancel: () => void;

  /** ダイアログを閉じる（背景タップ等） */
  onDismiss: () => void;

  /** 再試行ボタン押下時（エラー状態から） */
  onRetry?: () => void;
}

/**
 * ダイアログ内部で使用する状態
 */
export interface DialogInternalState {
  /** 現在のダイアログ状態 */
  state: DialogState;

  /** エラーメッセージ（state === 'error' の場合） */
  errorMessage?: string;

  /** 試行回数表示（state === 'connecting' の場合） */
  attemptInfo?: {
    current: number;
    max: number;
  };

  /** 入力されたパスワード（state === 'password' の場合） */
  passwordInput?: string;
}

/**
 * 期待される動作
 *
 * 1. visible=true で表示
 * 2. connection.autoReconnect=false の場合、'confirm' 状態から開始
 * 3. 「再接続」ボタン → onReconnect() 呼び出し
 * 4. 「キャンセル」ボタン → onCancel() 呼び出し
 * 5. 接続試行中は 'connecting' 状態でスピナー表示
 * 6. パスワード必要時は 'password' 状態でテキスト入力表示
 * 7. エラー時は 'error' 状態でメッセージ表示
 * 8. 成功時は自動的に閉じる（または 'success' 状態を経由）
 */
