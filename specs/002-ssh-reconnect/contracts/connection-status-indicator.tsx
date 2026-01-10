/**
 * ConnectionStatusIndicator Contract
 *
 * 接続状態インジケーターのインターフェース定義。
 * 実装は src/components/connection/ConnectionStatusIndicator.tsx に配置する。
 */

import type { ConnectionState } from '@/types/connection';

/**
 * インジケーターサイズ
 */
export type IndicatorSize = 'sm' | 'md' | 'lg';

/**
 * ConnectionStatusIndicatorのProps
 */
export interface ConnectionStatusIndicatorProps {
  /** 接続状態 */
  state: ConnectionState;

  /** サイズ (default: 'md') */
  size?: IndicatorSize;

  /** タップ時のコールバック */
  onPress?: () => void;

  /** 詳細情報を表示するかどうか (default: false) */
  showDetails?: boolean;

  /** アニメーションを有効にするか (default: true) */
  animated?: boolean;
}

/**
 * 状態ごとの表示仕様
 */
export const STATUS_DISPLAY = {
  connected: {
    color: '#22c55e',  // colors.success
    icon: 'circle',    // filled circle
    label: '接続中',
    animated: false,
  },
  connecting: {
    color: '#eab308',  // colors.warning
    icon: 'circle-outline',
    label: '接続中...',
    animated: true,    // パルスアニメーション
  },
  reconnecting: {
    color: '#eab308',  // colors.warning
    icon: 'refresh',   // 回転矢印
    label: '再接続中...',
    animated: true,    // 回転アニメーション
  },
  disconnected: {
    color: '#ef4444',  // colors.error
    icon: 'circle',
    label: '切断',
    animated: false,
  },
  error: {
    color: '#ef4444',  // colors.error
    icon: 'alert',
    label: 'エラー',
    animated: false,
  },
} as const;

/**
 * サイズごとの寸法
 */
export const SIZE_SPECS = {
  sm: {
    iconSize: 12,
    fontSize: 10,
    padding: 4,
  },
  md: {
    iconSize: 16,
    fontSize: 12,
    padding: 8,
  },
  lg: {
    iconSize: 20,
    fontSize: 14,
    padding: 12,
  },
} as const;

/**
 * 期待される動作
 *
 * 1. state.status に応じて色・アイコン・ラベルを表示
 * 2. onPress が指定されている場合、タップ可能な外観にする
 * 3. showDetails=true の場合、追加情報（切断時刻、エラー詳細等）を表示
 * 4. reconnecting 状態で attemptInfo がある場合、「再接続中 (2/3)」のように表示
 * 5. animated=true の場合、状態に応じたアニメーションを適用
 */
