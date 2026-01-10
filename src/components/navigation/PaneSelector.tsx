/**
 * PaneSelector
 *
 * tmuxペイン一覧を表示し選択可能にするコンポーネント。
 */
import { View, Pressable, Text, StyleSheet } from 'react-native';
import type { TmuxPane } from '@/types/tmux';

export interface PaneSelectorProps {
  /** ペイン一覧 */
  panes: TmuxPane[];
  /** 選択中のペインインデックス */
  selectedPane: number | null;
  /** ペイン選択時のコールバック */
  onSelect: (paneIndex: number) => void;
}

export function PaneSelector({ panes, selectedPane, onSelect }: PaneSelectorProps) {
  if (panes.length === 0) {
    return (
      <View style={styles.emptyContainer}>
        <Text style={styles.emptyText}>ペインがありません</Text>
      </View>
    );
  }

  // ペインが1つしかない場合は表示しない
  if (panes.length === 1) {
    return null;
  }

  return (
    <View style={styles.container}>
      {panes.map((pane) => (
        <Pressable
          key={pane.id}
          style={[
            styles.pane,
            pane.index === selectedPane && styles.paneActive,
          ]}
          onPress={() => onSelect(pane.index)}
        >
          <Text style={styles.paneId}>{pane.id}</Text>
          <Text
            style={[
              styles.paneCommand,
              pane.index === selectedPane && styles.paneCommandActive,
            ]}
            numberOfLines={1}
          >
            {pane.currentCommand}
          </Text>
          <Text style={styles.paneSize}>
            {pane.width}x{pane.height}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    flexWrap: 'wrap',
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
  pane: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
    backgroundColor: '#383A59',
    gap: 6,
  },
  paneActive: {
    backgroundColor: '#50FA7B',
  },
  paneId: {
    fontSize: 11,
    color: '#6272A4',
    fontFamily: 'monospace',
  },
  paneCommand: {
    fontSize: 12,
    color: '#F8F8F2',
    maxWidth: 80,
  },
  paneCommandActive: {
    color: '#282A36',
    fontWeight: 'bold',
  },
  paneSize: {
    fontSize: 10,
    color: '#6272A4',
    fontFamily: 'monospace',
  },
});
