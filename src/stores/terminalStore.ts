/**
 * ターミナルストア
 *
 * ペイン内容の状態を管理するZustandストア。
 */
import { create } from 'zustand';
import type { PaneContent, AnsiLine } from '@/types/terminal';

/**
 * ターミナルストアの状態
 */
interface TerminalStoreState {
  /** ペイン内容 (paneId -> content) */
  paneContents: Record<string, PaneContent>;
}

/**
 * ターミナルストアのアクション
 */
interface TerminalStoreActions {
  /** 内容を設定する */
  setContent: (paneId: string, content: PaneContent) => void;
  /** 行を追加する */
  appendLine: (paneId: string, line: AnsiLine) => void;
  /** 内容をクリアする */
  clearContent: (paneId: string) => void;
  /** すべての内容をクリアする */
  clearAllContents: () => void;
}

/**
 * デフォルトのスクロールバックサイズ
 */
const DEFAULT_SCROLLBACK_SIZE = 1000;

/**
 * ターミナルストア
 */
export const useTerminalStore = create<TerminalStoreState & TerminalStoreActions>((set) => ({
  // 初期状態
  paneContents: {},

  // 内容を設定する
  setContent: (paneId: string, content: PaneContent): void => {
    set((state) => ({
      paneContents: {
        ...state.paneContents,
        [paneId]: content,
      },
    }));
  },

  // 行を追加する
  appendLine: (paneId: string, line: AnsiLine): void => {
    set((state) => {
      const existing = state.paneContents[paneId];
      if (!existing) {
        return state;
      }

      // スクロールバック制限
      const lines = [...existing.lines, line];
      if (lines.length > DEFAULT_SCROLLBACK_SIZE) {
        lines.shift();
      }

      return {
        paneContents: {
          ...state.paneContents,
          [paneId]: {
            ...existing,
            lines,
            lastUpdated: Date.now(),
          },
        },
      };
    });
  },

  // 内容をクリアする
  clearContent: (paneId: string): void => {
    set((state) => {
      const { [paneId]: _, ...remaining } = state.paneContents;
      return { paneContents: remaining };
    });
  },

  // すべての内容をクリアする
  clearAllContents: (): void => {
    set({ paneContents: {} });
  },
}));
