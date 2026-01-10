/**
 * ANSIパーサー
 *
 * ANSIエスケープシーケンスをパースし、スタイル付きテキストに変換する。
 */
import type { AnsiSpan, AnsiLine } from '@/types/terminal';

/**
 * ANSIエスケープシーケンスの正規表現
 */
// eslint-disable-next-line no-control-regex
const ANSI_REGEX = /\x1b\[([0-9;]*)m/g;

/**
 * 現在のスタイル状態
 */
interface StyleState {
  fg?: number;
  bg?: number;
  bold?: boolean;
  dim?: boolean;
  italic?: boolean;
  underline?: boolean;
  blink?: boolean;
  inverse?: boolean;
  hidden?: boolean;
  strikethrough?: boolean;
}

/**
 * ANSIパーサー
 */
export class AnsiParser {
  /**
   * SGRコードをスタイル状態に適用する
   */
  private applySGR(state: StyleState, codes: number[]): StyleState {
    const newState = { ...state };
    let i = 0;

    while (i < codes.length) {
      const code = codes[i];

      if (code === undefined) {
        i++;
        continue;
      }

      // リセット
      if (code === 0) {
        return {};
      }

      // 属性
      if (code === 1) newState.bold = true;
      else if (code === 2) newState.dim = true;
      else if (code === 3) newState.italic = true;
      else if (code === 4) newState.underline = true;
      else if (code === 5) newState.blink = true;
      else if (code === 7) newState.inverse = true;
      else if (code === 8) newState.hidden = true;
      else if (code === 9) newState.strikethrough = true;

      // 属性リセット
      else if (code === 21) newState.bold = undefined;
      else if (code === 22) {
        newState.bold = undefined;
        newState.dim = undefined;
      }
      else if (code === 23) newState.italic = undefined;
      else if (code === 24) newState.underline = undefined;
      else if (code === 25) newState.blink = undefined;
      else if (code === 27) newState.inverse = undefined;
      else if (code === 28) newState.hidden = undefined;
      else if (code === 29) newState.strikethrough = undefined;

      // 前景色 (30-37, 90-97)
      else if (code >= 30 && code <= 37) {
        newState.fg = code - 30;
      }
      else if (code >= 90 && code <= 97) {
        newState.fg = code - 90 + 8; // bright colors
      }
      else if (code === 39) {
        newState.fg = undefined;
      }

      // 背景色 (40-47, 100-107)
      else if (code >= 40 && code <= 47) {
        newState.bg = code - 40;
      }
      else if (code >= 100 && code <= 107) {
        newState.bg = code - 100 + 8; // bright colors
      }
      else if (code === 49) {
        newState.bg = undefined;
      }

      // 256色 (38;5;n または 48;5;n)
      else if (code === 38 && codes[i + 1] === 5) {
        newState.fg = codes[i + 2];
        i += 2;
      }
      else if (code === 48 && codes[i + 1] === 5) {
        newState.bg = codes[i + 2];
        i += 2;
      }

      // 24bit色 (38;2;r;g;b または 48;2;r;g;b) - 現在は256色に変換せず無視
      else if (code === 38 && codes[i + 1] === 2) {
        // RGB to approximate 256 color index (simplified)
        const r = codes[i + 2] ?? 0;
        const g = codes[i + 3] ?? 0;
        const b = codes[i + 4] ?? 0;
        newState.fg = this.rgb256(r, g, b);
        i += 4;
      }
      else if (code === 48 && codes[i + 1] === 2) {
        const r = codes[i + 2] ?? 0;
        const g = codes[i + 3] ?? 0;
        const b = codes[i + 4] ?? 0;
        newState.bg = this.rgb256(r, g, b);
        i += 4;
      }

      i++;
    }

    return newState;
  }

  /**
   * RGBを256色インデックスに変換する
   */
  private rgb256(r: number, g: number, b: number): number {
    // 標準16色との近似
    if (r < 48 && g < 48 && b < 48) return 0; // black
    if (r > 207 && g > 207 && b > 207) return 15; // white

    // 6x6x6色キューブ (16-231)
    const ri = Math.round(r / 51);
    const gi = Math.round(g / 51);
    const bi = Math.round(b / 51);
    return 16 + 36 * ri + 6 * gi + bi;
  }

  /**
   * 行をパースする
   */
  parseLine(line: string): AnsiSpan[] {
    if (!line) {
      return [];
    }

    const spans: AnsiSpan[] = [];
    let state: StyleState = {};
    let lastIndex = 0;

    // リセットして新しい正規表現を使用
    const regex = new RegExp(ANSI_REGEX.source, 'g');
    let match: RegExpExecArray | null;

    while ((match = regex.exec(line)) !== null) {
      // マッチ前のテキストを追加
      if (match.index > lastIndex) {
        const text = line.slice(lastIndex, match.index);
        if (text) {
          spans.push(this.createSpan(text, state));
        }
      }

      // SGRコードを解析してスタイルを更新
      const codes = match[1] ? match[1].split(';').map((c) => parseInt(c, 10) || 0) : [0];
      state = this.applySGR(state, codes);

      lastIndex = regex.lastIndex;
    }

    // 残りのテキストを追加
    if (lastIndex < line.length) {
      const text = line.slice(lastIndex);
      if (text) {
        spans.push(this.createSpan(text, state));
      }
    }

    return spans;
  }

  /**
   * スパンを作成する
   */
  private createSpan(text: string, state: StyleState): AnsiSpan {
    const span: AnsiSpan = { text };

    if (state.fg !== undefined) span.fg = state.fg;
    if (state.bg !== undefined) span.bg = state.bg;
    if (state.bold) span.bold = true;
    if (state.dim) span.dim = true;
    if (state.italic) span.italic = true;
    if (state.underline) span.underline = true;
    if (state.blink) span.blink = true;
    if (state.inverse) span.inverse = true;
    if (state.hidden) span.hidden = true;
    if (state.strikethrough) span.strikethrough = true;

    return span;
  }

  /**
   * 複数行をパースする
   */
  parseLines(lines: string[]): AnsiLine[] {
    return lines.map((line) => ({ spans: this.parseLine(line) }));
  }

  /**
   * ANSIエスケープシーケンスを削除する
   */
  stripAnsi(text: string): string {
    return text.replace(ANSI_REGEX, '');
  }
}
