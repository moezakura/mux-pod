/**
 * useTerminal Hook
 *
 * ターミナル表示の更新とインタラクションを管理するカスタムフック。
 */
import { useCallback, useEffect, useRef } from 'react';
import { useTerminalStore } from '@/stores/terminalStore';
import { TmuxCommands } from '@/services/tmux/commands';
import { AnsiParser } from '@/services/ansi/parser';
import type { ISSHClient } from '@/services/ssh/client';
import type { PaneContent, AnsiLine } from '@/types/terminal';

/**
 * ポーリング間隔（ミリ秒）
 */
const POLLING_INTERVAL = 100;

/**
 * スクロールバック行数
 */
const SCROLLBACK_LINES = 1000;

/**
 * useTerminalの戻り値
 */
export interface UseTerminalResult {
  /** ペイン内容 */
  content: PaneContent | undefined;
  /** 行配列 */
  lines: AnsiLine[];
  /** カーソル位置 */
  cursor: { x: number; y: number };
  /** キーを送信する */
  sendKeys: (keys: string) => Promise<void>;
  /** 特殊キーを送信する */
  sendSpecialKey: (key: string) => Promise<void>;
  /** Ctrl+キーを送信する */
  sendCtrl: (key: string) => Promise<void>;
  /** ポーリングを開始する */
  startPolling: () => void;
  /** ポーリングを停止する */
  stopPolling: () => void;
  /** 内容を更新する */
  refresh: () => Promise<void>;
}

/**
 * ターミナルを管理するフック
 */
export function useTerminal(
  sshClient: ISSHClient | null,
  sessionName: string | null,
  windowIndex: number | null,
  paneIndex: number | null
): UseTerminalResult {
  const tmuxRef = useRef<TmuxCommands | null>(null);
  const parserRef = useRef(new AnsiParser());
  const pollingRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastContentRef = useRef<string>('');

  const { paneContents, setContent } = useTerminalStore();

  const paneId =
    sessionName && windowIndex !== null && paneIndex !== null
      ? `${sessionName}:${windowIndex}.${paneIndex}`
      : null;

  const content = paneId ? paneContents[paneId] : undefined;
  const lines = content?.lines ?? [];
  const cursor = {
    x: content?.cursorX ?? 0,
    y: content?.cursorY ?? 0,
  };

  // TmuxCommandsインスタンスの初期化
  useEffect(() => {
    if (sshClient) {
      tmuxRef.current = new TmuxCommands(sshClient);
    } else {
      tmuxRef.current = null;
    }
  }, [sshClient]);

  // 内容を更新する
  const refresh = useCallback(async (): Promise<void> => {
    if (!tmuxRef.current || !sessionName || windowIndex === null || paneIndex === null || !paneId) {
      return;
    }

    try {
      const rawLines = await tmuxRef.current.capturePane(
        sessionName,
        windowIndex,
        paneIndex,
        { start: -SCROLLBACK_LINES, escape: true }
      );

      // 変更チェック
      const contentString = rawLines.join('\n');
      if (contentString === lastContentRef.current) {
        return;
      }
      lastContentRef.current = contentString;

      // パース
      const parsedLines = parserRef.current.parseLines(rawLines);

      // ストアを更新
      setContent(paneId, {
        paneId,
        lines: parsedLines,
        scrollbackSize: parsedLines.length,
        cursorX: cursor.x,
        cursorY: cursor.y,
        lastUpdated: Date.now(),
      });
    } catch (error) {
      console.warn('Failed to capture pane:', error);
    }
  }, [sessionName, windowIndex, paneIndex, paneId, cursor.x, cursor.y, setContent]);

  // ポーリングを開始する
  const startPolling = useCallback((): void => {
    if (pollingRef.current) {
      return;
    }

    // 初回更新
    refresh();

    // ポーリング開始
    pollingRef.current = setInterval(refresh, POLLING_INTERVAL);
  }, [refresh]);

  // ポーリングを停止する
  const stopPolling = useCallback((): void => {
    if (pollingRef.current) {
      clearInterval(pollingRef.current);
      pollingRef.current = null;
    }
  }, []);

  // キーを送信する
  const sendKeys = useCallback(
    async (keys: string): Promise<void> => {
      if (!tmuxRef.current || !sessionName || windowIndex === null || paneIndex === null) {
        return;
      }

      await tmuxRef.current.sendKeys(sessionName, windowIndex, paneIndex, keys, true);
    },
    [sessionName, windowIndex, paneIndex]
  );

  // 特殊キーを送信する
  const sendSpecialKey = useCallback(
    async (key: string): Promise<void> => {
      if (!tmuxRef.current || !sessionName || windowIndex === null || paneIndex === null) {
        return;
      }

      await tmuxRef.current.sendKeys(sessionName, windowIndex, paneIndex, key, false);
    },
    [sessionName, windowIndex, paneIndex]
  );

  // Ctrl+キーを送信する
  const sendCtrl = useCallback(
    async (key: string): Promise<void> => {
      if (!tmuxRef.current || !sessionName || windowIndex === null || paneIndex === null) {
        return;
      }

      await tmuxRef.current.sendKeys(
        sessionName,
        windowIndex,
        paneIndex,
        `C-${key.toLowerCase()}`,
        false
      );
    },
    [sessionName, windowIndex, paneIndex]
  );

  // ペイン変更時にポーリングを再開
  useEffect(() => {
    if (paneId) {
      startPolling();
    }

    return () => {
      stopPolling();
    };
  }, [paneId, startPolling, stopPolling]);

  // クリーンアップ
  useEffect(() => {
    return () => {
      stopPolling();
    };
  }, [stopPolling]);

  return {
    content,
    lines,
    cursor,
    sendKeys,
    sendSpecialKey,
    sendCtrl,
    startPolling,
    stopPolling,
    refresh,
  };
}
