/**
 * Design Tokens
 *
 * HTMLデザインに完全一致するカラー、スペーシング、フォントサイズ等。
 * 参照: docs/screens/html/*.html
 */

/**
 * カラーパレット
 * HTMLデザインから抽出した正確な色
 */
export const colors = {
  // Primary
  primary: '#00c0d1',
  primaryDark: '#009aa8',

  // Backgrounds
  background: '#0e0e11',       // background-dark
  canvas: '#101116',           // canvas-dark
  surface: '#1E1F27',          // surface-dark / surface-elevated
  surfaceHighlight: '#2A2B35', // surface-highlight / key buttons
  surfaceLight: '#353640',     // hover state

  // Text
  text: '#FFFFFF',
  textSecondary: '#9ca3af',    // gray-400
  textMuted: '#6B7280',        // gray-500
  textDim: '#4B5563',          // gray-600

  // Borders
  border: '#2A2B36',
  borderLight: 'rgba(255, 255, 255, 0.05)',
  borderPrimary: 'rgba(0, 192, 209, 0.2)',

  // Terminal colors
  terminalGreen: '#22c55e',
  terminalYellow: '#eab308',
  terminalRed: '#ef4444',
  terminalBlue: '#3b82f6',
  terminalPurple: '#a855f7',

  // Status
  success: '#22c55e',    // green-500
  error: '#ef4444',      // red-500
  errorLight: '#f87171', // red-400
  warning: '#eab308',    // yellow-500

  // Error state badges/backgrounds
  errorBadgeBg: 'rgba(239, 68, 68, 0.1)',      // red-500/10
  errorBadgeBorder: 'rgba(239, 68, 68, 0.2)',  // red-500/20
  errorAccent: 'rgba(239, 68, 68, 0.4)',       // red-500/40

  // Log colors
  logBg: '#000000',
  logBorder: 'rgba(255, 255, 255, 0.1)',       // white/10
  logTimestamp: 'rgba(255, 255, 255, 0.5)',

  // Server icon background (active connection)
  serverIconBg: '#153e42',
  serverIconBorder: '#1f5f66',

  // Session badges
  badgeAttachedBg: 'rgba(22, 101, 52, 0.3)',    // green-900/30
  badgeAttachedBorder: 'rgba(22, 101, 52, 0.5)', // green-900/50
  badgeAttachedText: '#4ade80',                  // green-400
  badgeDetachedBg: '#1f2937',                    // gray-800
  badgeDetachedBorder: '#374151',                // gray-700
  badgeDetachedText: '#9ca3af',                  // gray-400

  // Overlay
  overlay: 'rgba(0, 0, 0, 0.5)',

  // Input
  inputBg: '#15161c',

  // Expanded content
  expandedBg: '#15161c',

  // Notification rule colors
  rose500: '#f43f5e',
  roseBg: 'rgba(244, 63, 94, 0.1)',
  roseBorder: 'rgba(244, 63, 94, 0.1)',
  roseText: '#fb7185',

  amber500: '#f59e0b',
  amberBg: 'rgba(245, 158, 11, 0.1)',
  amberBorder: 'rgba(245, 158, 11, 0.1)',
  amberText: '#fbbf24',

  emerald500: '#10b981',
  emeraldBg: 'rgba(16, 185, 129, 0.1)',
  emeraldBorder: 'rgba(16, 185, 129, 0.1)',
  emeraldText: '#34d399',

  // Surface darker (for forms)
  surfaceDarker: '#16171d',

  // Footer background (terminal screen)
  footerBg: '#14151a',
} as const;

/**
 * ボーダー半径
 * Tailwind準拠
 */
export const borderRadius = {
  none: 0,
  sm: 4,      // DEFAULT (0.25rem)
  md: 6,      // md (0.375rem)
  lg: 8,      // lg (0.5rem)
  xl: 12,     // xl (0.75rem)
  full: 9999,
} as const;

/**
 * スペーシング
 */
export const spacing = {
  px: 1,
  xs: 4,    // 1
  sm: 8,    // 2
  md: 16,   // 4
  lg: 24,   // 6
  xl: 32,   // 8
  xxl: 48,  // 12
} as const;

/**
 * フォントサイズ
 */
export const fontSize = {
  xxs: 9,   // 0.6rem 相当
  xs: 10,   // text-[10px]
  sm: 12,   // text-xs
  md: 14,   // text-sm
  lg: 16,   // text-base
  xl: 18,   // text-lg
  xxl: 24,  // text-2xl
  title: 28,
} as const;

/**
 * アイコンサイズ
 */
export const iconSize = {
  xs: 12,
  sm: 14,
  md: 16,
  lg: 18,
  xl: 20,
  xxl: 24,
} as const;

/**
 * シャドウ
 */
export const shadows = {
  glow: {
    shadowColor: '#00c0d1',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.3,
    shadowRadius: 10,
    elevation: 5,
  },
  card: {
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 3,
  },
  statusDot: {
    shadowColor: '#22c55e',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 8,
    elevation: 2,
  },
} as const;

/**
 * ターミナル表示用カラー
 */
export const terminalColors = {
  // ANSIカラー
  black: '#0e0e11',
  red: '#ef4444',
  green: '#22c55e',
  yellow: '#eab308',
  blue: '#3b82f6',
  magenta: '#a855f7',
  cyan: '#00c0d1',
  white: '#FFFFFF',

  // Bright variants
  brightBlack: '#4B5563',
  brightRed: '#f87171',
  brightGreen: '#4ade80',
  brightYellow: '#facc15',
  brightBlue: '#60a5fa',
  brightMagenta: '#c084fc',
  brightCyan: '#22d3ee',
  brightWhite: '#FFFFFF',

  // Special
  background: '#0e0e11',
  foreground: '#FFFFFF',
  cursor: '#00c0d1',
  selection: 'rgba(0, 192, 209, 0.3)',
} as const;

/**
 * ボトムナビゲーション
 */
export const bottomNav = {
  height: 72,
  iconSize: 24,
  labelSize: 10,
  activeIndicatorWidth: 32,
  activeIndicatorHeight: 2,
} as const;

/**
 * ヘッダー
 */
export const header = {
  height: 40,
  paddingHorizontal: 8,
} as const;

/**
 * 特殊キー
 */
export const specialKeys = {
  buttonHeight: 32,
  minWidth: 48,
  fontSize: 10,
  borderRadius: 4,
} as const;

/**
 * 矢印キー
 */
export const arrowKeys = {
  buttonSize: 36,
  smallButtonHeight: 17,
  iconSize: 14,
  largeIconSize: 16,
} as const;

/**
 * 入力バー
 */
export const inputBar = {
  height: 36,
  borderRadius: 4,
} as const;

/**
 * フォントファミリー
 *
 * Space Grotesk: UIテキスト用
 * JetBrains Mono: ターミナル/コード用
 */
export const fontFamily = {
  // Space Grotesk (UI)
  regular: 'SpaceGrotesk_400Regular',
  medium: 'SpaceGrotesk_500Medium',
  semibold: 'SpaceGrotesk_600SemiBold',
  bold: 'SpaceGrotesk_700Bold',

  // JetBrains Mono (Terminal/Code)
  mono: 'JetBrainsMono_400Regular',
  monoMedium: 'JetBrainsMono_500Medium',
  monoBold: 'JetBrainsMono_700Bold',
} as const;
