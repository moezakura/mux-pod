/**
 * tmuxコマンドサービス
 *
 * SSH経由でtmuxコマンドを実行し、結果をパースする。
 */
import type { ISSHClient } from '@/services/ssh/client';
import type { TmuxSession, TmuxWindow, TmuxPane } from '@/types/tmux';
import { parseSessions, parseWindows, parsePanes } from './parser';

/**
 * tmuxがインストールされていないエラー
 */
export class TmuxNotInstalledError extends Error {
  constructor() {
    super('tmux is not installed on the remote server');
    this.name = 'TmuxNotInstalledError';
  }
}

/**
 * tmuxコマンドエラー
 */
export class TmuxCommandError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TmuxCommandError';
  }
}

/**
 * ペインキャプチャオプション
 */
export interface CapturePaneOptions {
  /** 開始行（負の値でスクロールバック） */
  start?: number;
  /** 終了行 */
  end?: number;
  /** ANSIエスケープシーケンスを保持するか */
  escape?: boolean;
}

/**
 * tmuxコマンドサービス
 */
export class TmuxCommands {
  constructor(private sshClient: ISSHClient) {}

  /**
   * tmuxコマンドを実行する
   */
  private async exec(command: string): Promise<string> {
    try {
      return await this.sshClient.exec(command);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';

      if (message.includes('command not found') || message.includes('not found')) {
        throw new TmuxNotInstalledError();
      }

      throw new TmuxCommandError(message);
    }
  }

  /**
   * セッション一覧を取得する
   */
  async listSessions(): Promise<TmuxSession[]> {
    const format = '#{session_name}\t#{session_created}\t#{session_attached}\t#{session_windows}';
    const output = await this.exec(`tmux list-sessions -F "${format}" 2>/dev/null || true`);
    return parseSessions(output);
  }

  /**
   * 指定セッションのウィンドウ一覧を取得する
   */
  async listWindows(sessionName: string): Promise<TmuxWindow[]> {
    const format = '#{window_index}\t#{window_name}\t#{window_active}\t#{window_panes}';
    const output = await this.exec(
      `tmux list-windows -t "${sessionName}" -F "${format}" 2>/dev/null || true`
    );
    return parseWindows(output);
  }

  /**
   * 指定ウィンドウのペイン一覧を取得する
   */
  async listPanes(sessionName: string, windowIndex: number): Promise<TmuxPane[]> {
    const format =
      '#{pane_index}\t#{pane_id}\t#{pane_active}\t#{pane_current_command}\t#{pane_title}\t#{pane_width}\t#{pane_height}\t#{cursor_x}\t#{cursor_y}';
    const output = await this.exec(
      `tmux list-panes -t "${sessionName}:${windowIndex}" -F "${format}" 2>/dev/null || true`
    );
    return parsePanes(output);
  }

  /**
   * ペインの内容をキャプチャする
   */
  async capturePane(
    sessionName: string,
    windowIndex: number,
    paneIndex: number,
    options?: CapturePaneOptions
  ): Promise<string[]> {
    const target = `${sessionName}:${windowIndex}.${paneIndex}`;
    const args = [
      `-t "${target}"`,
      '-p', // stdout
    ];

    if (options?.escape !== false) {
      args.push('-e'); // ANSIエスケープシーケンスを保持
    }

    if (options?.start !== undefined) {
      args.push(`-S ${options.start}`);
    }

    if (options?.end !== undefined) {
      args.push(`-E ${options.end}`);
    }

    const output = await this.exec(`tmux capture-pane ${args.join(' ')} 2>/dev/null || true`);

    if (!output.trim()) {
      return [];
    }

    return output.split('\n');
  }

  /**
   * ペインにキー入力を送信する
   */
  async sendKeys(
    sessionName: string,
    windowIndex: number,
    paneIndex: number,
    keys: string,
    literal?: boolean
  ): Promise<void> {
    const target = `${sessionName}:${windowIndex}.${paneIndex}`;
    const args = [`-t "${target}"`];

    if (literal) {
      args.push('-l'); // リテラル（エスケープ解釈しない）
    }

    // キーをシングルクォートでエスケープ
    const escapedKeys = keys.replace(/'/g, "'\"'\"'");
    args.push(`'${escapedKeys}'`);

    await this.exec(`tmux send-keys ${args.join(' ')}`);
  }

  /**
   * ペインを選択する（アクティブにする）
   */
  async selectPane(
    sessionName: string,
    windowIndex: number,
    paneIndex: number
  ): Promise<void> {
    const target = `${sessionName}:${windowIndex}.${paneIndex}`;
    await this.exec(`tmux select-pane -t "${target}"`);
  }

  /**
   * ウィンドウを選択する
   */
  async selectWindow(sessionName: string, windowIndex: number): Promise<void> {
    const target = `${sessionName}:${windowIndex}`;
    await this.exec(`tmux select-window -t "${target}"`);
  }

  /**
   * ペインをリサイズする
   */
  async resizePane(
    sessionName: string,
    windowIndex: number,
    paneIndex: number,
    width: number,
    height: number
  ): Promise<void> {
    const target = `${sessionName}:${windowIndex}.${paneIndex}`;
    await this.exec(`tmux resize-pane -t "${target}" -x ${width} -y ${height}`);
  }
}

/**
 * 特殊キーマッピング
 */
export const SPECIAL_KEYS = {
  Enter: 'Enter',
  Escape: 'Escape',
  Tab: 'Tab',
  Backspace: 'BSpace',
  Delete: 'DC',
  Up: 'Up',
  Down: 'Down',
  Left: 'Left',
  Right: 'Right',
  Home: 'Home',
  End: 'End',
  PageUp: 'PPage',
  PageDown: 'NPage',
  Insert: 'IC',
  F1: 'F1',
  F2: 'F2',
  F3: 'F3',
  F4: 'F4',
  F5: 'F5',
  F6: 'F6',
  F7: 'F7',
  F8: 'F8',
  F9: 'F9',
  F10: 'F10',
  F11: 'F11',
  F12: 'F12',
} as const;

/**
 * Ctrl+キーを生成する
 */
export function ctrlKey(key: string): string {
  return `C-${key.toLowerCase()}`;
}

/**
 * Alt+キーを生成する
 */
export function altKey(key: string): string {
  return `M-${key}`;
}
