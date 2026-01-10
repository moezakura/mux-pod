/**
 * useLayout
 *
 * 画面サイズを検出し、大画面/折りたたみデバイス対応のレイアウト情報を提供する。
 */
import { useWindowDimensions } from 'react-native';
import { useMemo } from 'react';

/** レイアウトモード */
export type LayoutMode = 'compact' | 'expanded';

/** サイドバー幅 (HTMLデザイン: w-80 = 320px) */
export const SIDEBAR_WIDTH = 320;

/** 大画面と判定する最小幅 */
const EXPANDED_MIN_WIDTH = 600;

export interface LayoutInfo {
  /** 現在のレイアウトモード */
  mode: LayoutMode;
  /** 大画面かどうか */
  isExpanded: boolean;
  /** コンパクトモードかどうか */
  isCompact: boolean;
  /** 画面幅 */
  width: number;
  /** 画面高さ */
  height: number;
  /** サイドバー幅 */
  sidebarWidth: number;
  /** メインコンテンツ幅 */
  mainWidth: number;
}

/**
 * 画面サイズに基づいてレイアウト情報を取得する
 */
export function useLayout(): LayoutInfo {
  const { width, height } = useWindowDimensions();

  return useMemo(() => {
    const isExpanded = width >= EXPANDED_MIN_WIDTH;
    const mode: LayoutMode = isExpanded ? 'expanded' : 'compact';
    const sidebarWidth = isExpanded ? SIDEBAR_WIDTH : 0;
    const mainWidth = isExpanded ? width - SIDEBAR_WIDTH : width;

    return {
      mode,
      isExpanded,
      isCompact: !isExpanded,
      width,
      height,
      sidebarWidth,
      mainWidth,
    };
  }, [width, height]);
}
