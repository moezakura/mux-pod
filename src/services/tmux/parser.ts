/**
 * tmux出力パーサー
 *
 * tmuxコマンドの出力をパースしてオブジェクトに変換する。
 */
import type { TmuxSession, TmuxWindow, TmuxPane } from '@/types/tmux';

/**
 * セッション行をパースする
 * フォーマット: #{session_name}\t#{session_created}\t#{session_attached}\t#{session_windows}
 */
export function parseSessionLine(line: string): TmuxSession | null {
  const parts = line.trim().split('\t');
  if (parts.length < 4) {
    return null;
  }

  const [name, created, attached, windowCount] = parts;
  if (!name || !created || attached === undefined || !windowCount) {
    return null;
  }

  return {
    name,
    created: parseInt(created, 10) * 1000, // Unix timestamp to ms
    attached: attached === '1',
    windowCount: parseInt(windowCount, 10),
    windows: [],
  };
}

/**
 * ウィンドウ行をパースする
 * フォーマット: #{window_index}\t#{window_name}\t#{window_active}\t#{window_panes}
 */
export function parseWindowLine(line: string): TmuxWindow | null {
  const parts = line.trim().split('\t');
  if (parts.length < 4) {
    return null;
  }

  const [index, name, active, paneCount] = parts;
  if (index === undefined || !name || active === undefined || !paneCount) {
    return null;
  }

  return {
    index: parseInt(index, 10),
    name,
    active: active === '1',
    paneCount: parseInt(paneCount, 10),
    panes: [],
  };
}

/**
 * ペイン行をパースする
 * フォーマット: #{pane_index}\t#{pane_id}\t#{pane_active}\t#{pane_current_command}\t#{pane_title}\t#{pane_width}\t#{pane_height}\t#{cursor_x}\t#{cursor_y}
 */
export function parsePaneLine(line: string): TmuxPane | null {
  const parts = line.trim().split('\t');
  if (parts.length < 9) {
    return null;
  }

  const [index, id, active, currentCommand, title, width, height, cursorX, cursorY] = parts;
  if (
    index === undefined ||
    !id ||
    active === undefined ||
    !currentCommand ||
    !title ||
    !width ||
    !height ||
    cursorX === undefined ||
    cursorY === undefined
  ) {
    return null;
  }

  return {
    index: parseInt(index, 10),
    id,
    active: active === '1',
    currentCommand,
    title,
    width: parseInt(width, 10),
    height: parseInt(height, 10),
    cursorX: parseInt(cursorX, 10),
    cursorY: parseInt(cursorY, 10),
  };
}

/**
 * セッション一覧をパースする
 */
export function parseSessions(output: string): TmuxSession[] {
  const lines = output.trim().split('\n').filter((line) => line.trim());
  return lines
    .map(parseSessionLine)
    .filter((session): session is TmuxSession => session !== null);
}

/**
 * ウィンドウ一覧をパースする
 */
export function parseWindows(output: string): TmuxWindow[] {
  const lines = output.trim().split('\n').filter((line) => line.trim());
  return lines
    .map(parseWindowLine)
    .filter((window): window is TmuxWindow => window !== null);
}

/**
 * ペイン一覧をパースする
 */
export function parsePanes(output: string): TmuxPane[] {
  const lines = output.trim().split('\n').filter((line) => line.trim());
  return lines
    .map(parsePaneLine)
    .filter((pane): pane is TmuxPane => pane !== null);
}
