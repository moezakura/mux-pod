/**
 * WindowTabs
 *
 * tmuxウィンドウ一覧をタブ形式で表示するコンポーネント。
 */
import { ScrollView, Pressable, Text, StyleSheet, View } from 'react-native';
import type { TmuxWindow } from '@/types/tmux';

export interface WindowTabsProps {
  /** ウィンドウ一覧 */
  windows: TmuxWindow[];
  /** 選択中のウィンドウインデックス */
  selectedWindow: number | null;
  /** ウィンドウ選択時のコールバック */
  onSelect: (windowIndex: number) => void;
}

export function WindowTabs({ windows, selectedWindow, onSelect }: WindowTabsProps) {
  if (windows.length === 0) {
    return (
      <View style={styles.emptyContainer}>
        <Text style={styles.emptyText}>ウィンドウがありません</Text>
      </View>
    );
  }

  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.container}
    >
      {windows.map((window) => (
        <Pressable
          key={window.index}
          style={[
            styles.tab,
            window.index === selectedWindow && styles.tabActive,
          ]}
          onPress={() => onSelect(window.index)}
        >
          <Text style={styles.index}>{window.index}:</Text>
          <Text
            style={[
              styles.tabText,
              window.index === selectedWindow && styles.tabTextActive,
            ]}
            numberOfLines={1}
          >
            {window.name}
          </Text>
          {window.active && <Text style={styles.activeBadge}>*</Text>}
        </Pressable>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    gap: 4,
  },
  emptyContainer: {
    padding: 16,
    alignItems: 'center',
  },
  emptyText: {
    color: '#6272A4',
    fontSize: 14,
  },
  tab: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 6,
    backgroundColor: '#383A59',
    gap: 4,
  },
  tabActive: {
    backgroundColor: '#8BE9FD',
  },
  index: {
    fontSize: 12,
    color: '#6272A4',
  },
  tabText: {
    color: '#F8F8F2',
    fontSize: 13,
  },
  tabTextActive: {
    fontWeight: 'bold',
    color: '#282A36',
  },
  activeBadge: {
    fontSize: 10,
    color: '#F1FA8C',
    fontWeight: 'bold',
  },
});
