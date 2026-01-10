/**
 * SessionTabs
 *
 * tmuxセッション一覧をタブ形式で表示するコンポーネント。
 */
import { ScrollView, Pressable, Text, StyleSheet, View } from 'react-native';
import type { TmuxSession } from '@/types/tmux';

export interface SessionTabsProps {
  /** セッション一覧 */
  sessions: TmuxSession[];
  /** 選択中のセッション名 */
  selectedSession: string | null;
  /** セッション選択時のコールバック */
  onSelect: (sessionName: string) => void;
}

export function SessionTabs({ sessions, selectedSession, onSelect }: SessionTabsProps) {
  if (sessions.length === 0) {
    return (
      <View style={styles.emptyContainer}>
        <Text style={styles.emptyText}>セッションがありません</Text>
      </View>
    );
  }

  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.container}
    >
      {sessions.map((session) => (
        <Pressable
          key={session.name}
          style={[
            styles.tab,
            session.name === selectedSession && styles.tabActive,
          ]}
          onPress={() => onSelect(session.name)}
        >
          <Text
            style={[
              styles.tabText,
              session.name === selectedSession && styles.tabTextActive,
            ]}
            numberOfLines={1}
          >
            {session.name}
          </Text>
          {session.attached && <Text style={styles.attachedBadge}>⚫</Text>}
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
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: '#44475A',
    gap: 4,
  },
  tabActive: {
    backgroundColor: '#BD93F9',
  },
  tabText: {
    color: '#F8F8F2',
    fontSize: 14,
  },
  tabTextActive: {
    fontWeight: 'bold',
    color: '#282A36',
  },
  attachedBadge: {
    fontSize: 8,
    color: '#50FA7B',
  },
});
