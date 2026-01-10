/**
 * ANSIスタイル付きテキストスパン
 *
 * 同一スタイルのテキスト断片を表す。
 */
export interface AnsiSpan {
  /** テキスト内容 */
  text: string;
  /** 前景色 (0-255, undefined=default) */
  fg?: number;
  /** 背景色 (0-255, undefined=default) */
  bg?: number;
  /** 太字 */
  bold?: boolean;
  /** 薄字 */
  dim?: boolean;
  /** イタリック */
  italic?: boolean;
  /** 下線 */
  underline?: boolean;
  /** 点滅 */
  blink?: boolean;
  /** 反転 */
  inverse?: boolean;
  /** 非表示 */
  hidden?: boolean;
  /** 取り消し線 */
  strikethrough?: boolean;
}

/**
 * パース済みANSI行
 */
export interface AnsiLine {
  /** スパン配列 */
  spans: AnsiSpan[];
}

/**
 * ペインの表示内容
 *
 * ポーリングで更新されるペインの内容を表す。
 */
export interface PaneContent {
  /** 対応するペインID */
  paneId: string;
  /** 行ごとの内容（パース済み） */
  lines: AnsiLine[];
  /** スクロールバック行数 */
  scrollbackSize: number;
  /** カーソルX位置 */
  cursorX: number;
  /** カーソルY位置 */
  cursorY: number;
  /** 最終更新日時 (Unix timestamp ms) */
  lastUpdated: number;
}

/**
 * ターミナルテーマ定義
 */
export interface TerminalTheme {
  /** 背景色 */
  background: string;
  /** 前景色（デフォルト） */
  foreground: string;
  /** カーソル色 */
  cursor: string;
  /** 選択色 */
  selection: string;
  /** 16色パレット */
  palette: readonly [
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string,
    string
  ];
}

/**
 * Draculaテーマ
 */
export const DRACULA_THEME: TerminalTheme = {
  background: '#282A36',
  foreground: '#F8F8F2',
  cursor: '#F8F8F2',
  selection: '#44475A',
  palette: [
    '#21222C',
    '#FF5555',
    '#50FA7B',
    '#F1FA8C',
    '#BD93F9',
    '#FF79C6',
    '#8BE9FD',
    '#F8F8F2',
    '#6272A4',
    '#FF6E6E',
    '#69FF94',
    '#FFFFA5',
    '#D6ACFF',
    '#FF92DF',
    '#A4FFFF',
    '#FFFFFF',
  ],
};

/**
 * MuxPodテーマ
 * HTMLデザインに完全準拠したカラーパレット
 */
export const MUXPOD_THEME: TerminalTheme = {
  background: '#0e0e11',
  foreground: '#FFFFFF',
  cursor: '#00c0d1',
  selection: 'rgba(0, 192, 209, 0.3)',
  palette: [
    '#0e0e11',  // Black
    '#ef4444',  // Red
    '#22c55e',  // Green
    '#eab308',  // Yellow
    '#3b82f6',  // Blue
    '#a855f7',  // Magenta
    '#00c0d1',  // Cyan
    '#FFFFFF',  // White
    '#4B5563',  // Bright Black
    '#f87171',  // Bright Red
    '#4ade80',  // Bright Green
    '#facc15',  // Bright Yellow
    '#60a5fa',  // Bright Blue
    '#c084fc',  // Bright Magenta
    '#22d3ee',  // Bright Cyan
    '#FFFFFF',  // Bright White
  ],
};
