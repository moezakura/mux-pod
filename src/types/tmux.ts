/**
 * tmuxセッション
 *
 * SSH経由で取得したtmuxセッション情報を表す。
 */
export interface TmuxSession {
  /** セッション名 (unique per server) */
  name: string;
  /** 作成日時 (Unix timestamp ms) */
  created: number;
  /** 他クライアントがアタッチ中か */
  attached: boolean;
  /** ウィンドウ数 */
  windowCount: number;
  /** 所属ウィンドウ (lazy load) */
  windows: TmuxWindow[];
}

/**
 * tmuxウィンドウ
 */
export interface TmuxWindow {
  /** ウィンドウインデックス (0-based) */
  index: number;
  /** ウィンドウ名 */
  name: string;
  /** アクティブウィンドウか */
  active: boolean;
  /** ペイン数 */
  paneCount: number;
  /** 所属ペイン (lazy load) */
  panes: TmuxPane[];
}

/**
 * tmuxペイン
 */
export interface TmuxPane {
  /** ペインインデックス (0-based) */
  index: number;
  /** ペインID (%0, %1, etc.) */
  id: string;
  /** アクティブペインか */
  active: boolean;
  /** 現在実行中のコマンド */
  currentCommand: string;
  /** ペインタイトル */
  title: string;
  /** 幅（カラム数） */
  width: number;
  /** 高さ（行数） */
  height: number;
  /** カーソルX位置 */
  cursorX: number;
  /** カーソルY位置 */
  cursorY: number;
}

/**
 * ペインターゲット指定子
 */
export interface PaneTarget {
  session: string;
  windowIndex: number;
  paneIndex: number;
}

/**
 * ペインターゲットを文字列に変換する
 * @example formatPaneTarget({ session: "main", windowIndex: 0, paneIndex: 1 }) // "main:0.1"
 */
export function formatPaneTarget(target: PaneTarget): string {
  return `${target.session}:${target.windowIndex}.${target.paneIndex}`;
}
