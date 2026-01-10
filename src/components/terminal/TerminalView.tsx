/**
 * TerminalView
 *
 * ANSIカラー対応のターミナル表示コンポーネント。
 */
import { memo, useCallback, useRef } from 'react';
import { View, Text, FlatList, StyleSheet, type ListRenderItemInfo } from 'react-native';
import type { AnsiLine, AnsiSpan, TerminalTheme } from '@/types/terminal';
import { MUXPOD_THEME } from '@/types/terminal';

export interface TerminalViewProps {
  /** 表示する行 */
  lines: AnsiLine[];
  /** テーマ */
  theme?: TerminalTheme;
  /** フォントサイズ */
  fontSize?: number;
  /** 行の高さ */
  lineHeight?: number;
}

/**
 * 16色パレット
 */
const ANSI_16_COLORS: Record<number, string> = {
  0: '#000000',
  1: '#CC0000',
  2: '#00CC00',
  3: '#CCCC00',
  4: '#0000CC',
  5: '#CC00CC',
  6: '#00CCCC',
  7: '#CCCCCC',
  8: '#666666',
  9: '#FF0000',
  10: '#00FF00',
  11: '#FFFF00',
  12: '#0000FF',
  13: '#FF00FF',
  14: '#00FFFF',
  15: '#FFFFFF',
};

/**
 * ANSIカラーインデックスを16進カラーに変換
 */
function ansiToHex(colorIndex: number, theme: TerminalTheme): string {
  // 標準16色
  if (colorIndex < 16) {
    return theme.palette[colorIndex] ?? ANSI_16_COLORS[colorIndex] ?? theme.foreground;
  }

  // 6x6x6色キューブ (16-231)
  if (colorIndex < 232) {
    const index = colorIndex - 16;
    const r = Math.floor(index / 36);
    const g = Math.floor((index % 36) / 6);
    const b = index % 6;
    const toHex = (v: number) =>
      (v === 0 ? 0 : 55 + v * 40).toString(16).padStart(2, '0');
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
  }

  // グレースケール (232-255)
  const gray = (colorIndex - 232) * 10 + 8;
  const hex = gray.toString(16).padStart(2, '0');
  return `#${hex}${hex}${hex}`;
}

/**
 * スパンコンポーネント
 */
const TerminalSpan = memo(function TerminalSpan({
  span,
  theme,
  fontSize,
}: {
  span: AnsiSpan;
  theme: TerminalTheme;
  fontSize: number;
}) {
  // HTMLデザイン準拠: text-white/90 font-light tracking-tight
  const style: Record<string, unknown> = {
    fontSize,
    fontFamily: 'monospace',
    color: 'rgba(255, 255, 255, 0.9)',  // text-white/90
    fontWeight: '300',  // font-light
    letterSpacing: -0.5,  // tracking-tight
  };

  if (span.fg !== undefined) {
    style.color = ansiToHex(span.fg, theme);
  }
  if (span.bg !== undefined) {
    style.backgroundColor = ansiToHex(span.bg, theme);
  }
  if (span.bold) {
    style.fontWeight = 'bold';
  }
  if (span.italic) {
    style.fontStyle = 'italic';
  }
  if (span.underline) {
    style.textDecorationLine = 'underline';
  }
  if (span.strikethrough) {
    style.textDecorationLine = span.underline ? 'underline line-through' : 'line-through';
  }
  if (span.dim) {
    style.opacity = 0.5;
  }
  if (span.inverse) {
    const tmpColor = style.color;
    style.color = style.backgroundColor ?? theme.background;
    style.backgroundColor = tmpColor;
  }
  if (span.hidden) {
    style.opacity = 0;
  }

  return <Text style={style}>{span.text}</Text>;
});

/**
 * 行コンポーネント
 */
const TerminalLine = memo(function TerminalLine({
  line,
  theme,
  fontSize,
  lineHeight,
}: {
  line: AnsiLine;
  theme: TerminalTheme;
  fontSize: number;
  lineHeight: number;
}) {
  if (line.spans.length === 0) {
    return <View style={{ height: lineHeight }} />;
  }

  return (
    <View style={[styles.line, { minHeight: lineHeight }]}>
      {line.spans.map((span, index) => (
        <TerminalSpan key={index} span={span} theme={theme} fontSize={fontSize} />
      ))}
    </View>
  );
});

/**
 * TerminalView
 *
 * HTMLデザイン準拠:
 * - p-2 (padding: 8px)
 * - font-mono text-xs (12px)
 * - leading-snug (lineHeight: 1.375)
 * - text-white/90 font-light tracking-tight
 */
export function TerminalView({
  lines,
  theme = MUXPOD_THEME,
  fontSize = 12,
  lineHeight = 17,  // 12px * 1.375 ≈ 17px (leading-snug)
}: TerminalViewProps) {
  const flatListRef = useRef<FlatList>(null);

  const renderItem = useCallback(
    ({ item }: ListRenderItemInfo<AnsiLine>) => (
      <TerminalLine
        line={item}
        theme={theme}
        fontSize={fontSize}
        lineHeight={lineHeight}
      />
    ),
    [theme, fontSize, lineHeight]
  );

  const keyExtractor = useCallback(
    (_item: AnsiLine, index: number) => String(index),
    []
  );

  // 新しい内容が追加されたら下にスクロール
  const onContentSizeChange = useCallback(() => {
    flatListRef.current?.scrollToEnd({ animated: false });
  }, []);

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <FlatList
        ref={flatListRef}
        data={lines}
        renderItem={renderItem}
        keyExtractor={keyExtractor}
        onContentSizeChange={onContentSizeChange}
        initialNumToRender={50}
        maxToRenderPerBatch={50}
        windowSize={21}
        removeClippedSubviews
        showsVerticalScrollIndicator
        contentContainerStyle={styles.content}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  line: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
});
