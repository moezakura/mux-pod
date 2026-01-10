/**
 * ホーム画面（接続一覧）
 *
 * HTMLデザイン (server_connections_list.html) に完全準拠。
 */
import { useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  Modal,
  Alert,
  SafeAreaView,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useConnectionStore } from '@/stores/connectionStore';
import { ConnectionList } from '@/components/connection/ConnectionList';
import { useSSH } from '@/hooks/useSSH';
import { colors, spacing, fontSize, borderRadius, bottomNav, shadows } from '@/theme';
import type { Connection } from '@/types/connection';

/**
 * ヘッダーコンポーネント
 */
function Header() {
  return (
    <View style={styles.header}>
      <View style={styles.headerLeft}>
        <Text style={styles.headerTitle}>Connections</Text>
        <Text style={styles.headerSubtitle}>GATEWAY_STATUS: ONLINE</Text>
      </View>
      <View style={styles.headerActions}>
        <Pressable
          style={({ pressed }) => [
            styles.headerButton,
            pressed && styles.headerButtonPressed,
          ]}
        >
          <MaterialCommunityIcons
            name="magnify"
            size={24}
            color={colors.textSecondary}
          />
        </Pressable>
        <Pressable
          style={({ pressed }) => [
            styles.headerButton,
            pressed && styles.headerButtonPressed,
          ]}
        >
          <MaterialCommunityIcons
            name="sort"
            size={24}
            color={colors.textSecondary}
          />
        </Pressable>
      </View>
    </View>
  );
}

/**
 * FABボタン
 */
function FABButton({ onPress }: { onPress: () => void }) {
  return (
    <View style={styles.fabContainer}>
      <Pressable
        style={({ pressed }) => [
          styles.fab,
          pressed && styles.fabPressed,
        ]}
        onPress={onPress}
      >
        <MaterialCommunityIcons name="plus" size={24} color={colors.background} />
        <Text style={styles.fabText}>Add New Connection</Text>
      </Pressable>
    </View>
  );
}

/**
 * ボトムナビゲーション
 */
function BottomNavigation({ activeTab }: { activeTab: string }) {
  const tabs = [
    { id: 'net', label: 'Net', icon: 'lan' as const },
    { id: 'term', label: 'Term', icon: 'console' as const },
    { id: 'keys', label: 'Keys', icon: 'key' as const },
    { id: 'settings', label: 'Settings', icon: 'cog' as const },
  ];

  return (
    <View style={styles.bottomNav}>
      {tabs.map((tab) => {
        const isActive = activeTab === tab.id;
        return (
          <Pressable
            key={tab.id}
            style={styles.navItem}
          >
            {isActive && <View style={styles.navIndicator} />}
            <MaterialCommunityIcons
              name={tab.icon}
              size={bottomNav.iconSize}
              color={isActive ? colors.primary : colors.textMuted}
            />
            <Text
              style={[
                styles.navLabel,
                isActive && styles.navLabelActive,
              ]}
            >
              {tab.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export default function HomeScreen() {
  const router = useRouter();
  const { connections, connectionStates, removeConnection } = useConnectionStore();
  const { connect, isConnecting } = useSSH();

  const [menuVisible, setMenuVisible] = useState(false);
  const [selectedConnection, setSelectedConnection] = useState<Connection | null>(null);

  // 接続をタップしたとき
  const handleConnectionPress = useCallback(
    async (connection: Connection) => {
      try {
        await connect(connection.id);
        router.push(`/(main)/terminal/${connection.id}`);
      } catch (error) {
        Alert.alert(
          '接続エラー',
          error instanceof Error ? error.message : '接続に失敗しました'
        );
      }
    },
    [connect, router]
  );

  // 接続をロングプレスしたとき
  const handleConnectionLongPress = useCallback((connection: Connection) => {
    setSelectedConnection(connection);
    setMenuVisible(true);
  }, []);

  // 編集をタップしたとき
  const handleEdit = useCallback(() => {
    if (selectedConnection) {
      setMenuVisible(false);
      router.push(`/connection/${selectedConnection.id}/edit`);
    }
  }, [selectedConnection, router]);

  // 削除をタップしたとき
  const handleDelete = useCallback(() => {
    if (selectedConnection) {
      setMenuVisible(false);
      Alert.alert(
        '接続を削除',
        `「${selectedConnection.name}」を削除しますか？\nこの操作は取り消せません。`,
        [
          { text: 'キャンセル', style: 'cancel' },
          {
            text: '削除',
            style: 'destructive',
            onPress: () => {
              removeConnection(selectedConnection.id);
            },
          },
        ]
      );
    }
  }, [selectedConnection, removeConnection]);

  // 新規接続追加
  const handleAddConnection = useCallback(() => {
    router.push('/connection/add');
  }, [router]);

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor={colors.canvas} />

      <Header />

      <View style={styles.content}>
        <ConnectionList
          connections={connections}
          connectionStates={connectionStates}
          onConnectionPress={handleConnectionPress}
          onConnectionLongPress={handleConnectionLongPress}
        />
      </View>

      <FABButton onPress={handleAddConnection} />

      <BottomNavigation activeTab="net" />

      {isConnecting && (
        <View style={styles.loadingOverlay}>
          <View style={styles.loadingBox}>
            <ActivityIndicator size="small" color={colors.primary} />
            <Text style={styles.loadingText}>接続中...</Text>
          </View>
        </View>
      )}

      {/* コンテキストメニュー */}
      <Modal
        visible={menuVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setMenuVisible(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setMenuVisible(false)}
        >
          <View style={styles.menu}>
            <Text style={styles.menuTitle}>{selectedConnection?.name}</Text>
            <Pressable
              style={({ pressed }) => [
                styles.menuItem,
                pressed && styles.menuItemPressed,
              ]}
              onPress={handleEdit}
            >
              <MaterialCommunityIcons name="pencil" size={20} color={colors.text} />
              <Text style={styles.menuItemText}>編集</Text>
            </Pressable>
            <Pressable
              style={({ pressed }) => [
                styles.menuItem,
                pressed && styles.menuItemPressed,
              ]}
              onPress={handleDelete}
            >
              <MaterialCommunityIcons name="delete" size={20} color={colors.error} />
              <Text style={[styles.menuItemText, styles.deleteText]}>削除</Text>
            </Pressable>
            <Pressable
              style={({ pressed }) => [
                styles.menuItem,
                styles.cancelItem,
                pressed && styles.menuItemPressed,
              ]}
              onPress={() => setMenuVisible(false)}
            >
              <Text style={styles.menuItemText}>キャンセル</Text>
            </Pressable>
          </View>
        </Pressable>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xxl,
    paddingBottom: spacing.md,
    backgroundColor: colors.canvas,
    borderBottomWidth: 1,
    borderBottomColor: colors.surface,
  },
  headerLeft: {
    flex: 1,
  },
  headerTitle: {
    fontSize: fontSize.xxl,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: -0.5,
  },
  headerSubtitle: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    marginTop: spacing.xs,
    fontFamily: 'monospace',
  },
  headerActions: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  headerButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerButtonPressed: {
    backgroundColor: colors.surface,
  },
  content: {
    flex: 1,
    paddingTop: spacing.md,
    paddingBottom: 140,
  },
  fabContainer: {
    position: 'absolute',
    bottom: bottomNav.height + spacing.md,
    left: 0,
    right: 0,
    alignItems: 'flex-end',
    paddingRight: spacing.md,
  },
  fab: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.primary,
    paddingHorizontal: spacing.lg,
    height: 56,
    borderRadius: borderRadius.xl,
    gap: spacing.sm,
    ...shadows.glow,
  },
  fabPressed: {
    opacity: 0.9,
    transform: [{ scale: 0.98 }],
  },
  fabText: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.background,
    letterSpacing: -0.3,
  },
  bottomNav: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    backgroundColor: 'rgba(14, 14, 17, 0.9)',
    borderTopWidth: 1,
    borderTopColor: colors.surface,
    height: bottomNav.height,
    paddingBottom: spacing.sm,
  },
  navItem: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: spacing.sm,
    gap: spacing.xs,
  },
  navIndicator: {
    position: 'absolute',
    top: -1,
    width: bottomNav.activeIndicatorWidth,
    height: bottomNav.activeIndicatorHeight,
    backgroundColor: colors.primary,
    borderRadius: 1,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: 5,
    elevation: 3,
  },
  navLabel: {
    fontSize: bottomNav.labelSize,
    fontWeight: '500',
    color: colors.textMuted,
    letterSpacing: 0.3,
  },
  navLabelActive: {
    color: colors.primary,
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: colors.overlay,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    gap: spacing.sm,
  },
  loadingText: {
    fontSize: fontSize.md,
    color: colors.text,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: colors.overlay,
    justifyContent: 'center',
    alignItems: 'center',
  },
  menu: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    padding: spacing.sm,
    width: '80%',
    maxWidth: 300,
    borderWidth: 1,
    borderColor: colors.border,
  },
  menuTitle: {
    fontSize: fontSize.lg,
    fontWeight: '600',
    color: colors.text,
    textAlign: 'center',
    padding: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.md,
    borderRadius: borderRadius.lg,
    gap: spacing.sm,
  },
  menuItemPressed: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  menuItemText: {
    fontSize: fontSize.lg,
    color: colors.text,
  },
  deleteText: {
    color: colors.error,
  },
  cancelItem: {
    marginTop: spacing.sm,
    backgroundColor: colors.surfaceHighlight,
    justifyContent: 'center',
  },
});
