/**
 * Text
 *
 * テーマ対応のTextコンポーネント。
 * Space Grotesk (UI) / JetBrains Mono (Terminal) をサポート。
 */
import { memo } from 'react';
import { Text as RNText, StyleSheet, type TextProps as RNTextProps } from 'react-native';
import { colors, fontSize, fontFamily } from '@/theme';

type FontVariant = 'regular' | 'medium' | 'semibold' | 'bold';
type MonoVariant = 'mono' | 'monoMedium' | 'monoBold';
type TextSize = 'xxs' | 'xs' | 'sm' | 'md' | 'lg' | 'xl' | 'xxl' | 'title';
type TextColor = 'primary' | 'secondary' | 'muted' | 'dim' | 'error' | 'success' | 'warning';

export interface TextProps extends RNTextProps {
  /** フォントバリアント (UI用) */
  variant?: FontVariant;
  /** 等幅フォント使用時のバリアント */
  mono?: boolean | MonoVariant;
  /** テキストサイズ */
  size?: TextSize;
  /** テキストカラー */
  color?: TextColor;
  /** 子要素 */
  children?: React.ReactNode;
}

const colorMap: Record<TextColor, string> = {
  primary: colors.text,
  secondary: colors.textSecondary,
  muted: colors.textMuted,
  dim: colors.textDim,
  error: colors.error,
  success: colors.success,
  warning: colors.warning,
};

/**
 * Text コンポーネント
 */
export const Text = memo(function Text({
  variant = 'regular',
  mono,
  size = 'md',
  color = 'primary',
  style,
  children,
  ...props
}: TextProps) {
  // フォントファミリーを決定
  let ff: string;
  if (mono) {
    if (typeof mono === 'string') {
      ff = fontFamily[mono];
    } else {
      ff = fontFamily.mono;
    }
  } else {
    ff = fontFamily[variant];
  }

  return (
    <RNText
      style={[
        styles.base,
        { fontFamily: ff },
        { fontSize: fontSize[size] },
        { color: colorMap[color] },
        style,
      ]}
      {...props}
    >
      {children}
    </RNText>
  );
});

const styles = StyleSheet.create({
  base: {
    includeFontPadding: false,
  },
});
