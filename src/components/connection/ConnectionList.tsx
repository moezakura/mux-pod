/**
 * ConnectionList
 *
 * 接続一覧を表示するリストコンポーネント。
 */
import { View, Text, FlatList, StyleSheet, type GestureResponderEvent } from 'react-native';
import { ConnectionCard } from './ConnectionCard';
import type { Connection, ConnectionState } from '@/types/connection';

export interface ConnectionListProps {
  /** 接続一覧 */
  connections: Connection[];
  /** 接続状態のマップ */
  connectionStates: Record<string, ConnectionState>;
  /** 接続タップ時のコールバック */
  onConnectionPress?: (connection: Connection) => void;
  /** 接続ロングプレス時のコールバック */
  onConnectionLongPress?: (connection: Connection, event: GestureResponderEvent) => void;
  /** リフレッシュ中かどうか */
  refreshing?: boolean;
  /** リフレッシュ時のコールバック */
  onRefresh?: () => void;
}

export function ConnectionList({
  connections,
  connectionStates,
  onConnectionPress,
  onConnectionLongPress,
  refreshing,
  onRefresh,
}: ConnectionListProps) {
  if (connections.length === 0) {
    return (
      <View style={styles.emptyContainer}>
        <Text style={styles.emptyIcon}>📡</Text>
        <Text style={styles.emptyTitle}>接続がありません</Text>
        <Text style={styles.emptySubtitle}>
          右下の + ボタンから新しい接続を追加してください
        </Text>
      </View>
    );
  }

  return (
    <FlatList
      data={connections}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => (
        <ConnectionCard
          connection={item}
          state={connectionStates[item.id]}
          onPress={() => onConnectionPress?.(item)}
          onLongPress={(event) => onConnectionLongPress?.(item, event)}
        />
      )}
      contentContainerStyle={styles.list}
      refreshing={refreshing}
      onRefresh={onRefresh}
      testID="connection-list"
    />
  );
}

const styles = StyleSheet.create({
  list: {
    paddingVertical: 8,
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
  },
  emptyIcon: {
    fontSize: 64,
    marginBottom: 16,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#F8F8F2',
    marginBottom: 8,
  },
  emptySubtitle: {
    fontSize: 14,
    color: '#6272A4',
    textAlign: 'center',
  },
});
