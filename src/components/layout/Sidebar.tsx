/**
 * Sidebar
 *
 * 大画面用サイドバー。接続一覧とtmuxセッション/ウィンドウ/ペインのツリー表示。
 * HTMLデザイン: foldable_large_screen_view.html 参照
 */
import { View, Text, ScrollView, Pressable, StyleSheet } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { colors, spacing, fontSize, borderRadius } from '@/theme';
import { SIDEBAR_WIDTH } from '@/hooks/useLayout';
import type { Connection, ConnectionState } from '@/types/connection';
import type { TmuxSession, TmuxWindow, TmuxPane } from '@/types/tmux';

export interface SidebarProps {
  /** 接続一覧 */
  connections: Connection[];
  /** 接続状態のマップ */
  connectionStates: Record<string, ConnectionState>;
  /** アクティブな接続ID */
  activeConnectionId?: string;
  /** 接続タップ時 */
  onConnectionPress?: (connection: Connection) => void;
  /** tmuxセッション一覧 */
  sessions?: TmuxSession[];
  /** 選択中のセッション */
  selectedSession?: string;
  /** 選択中のウィンドウ */
  selectedWindow?: number;
  /** 選択中のペイン */
  selectedPane?: number;
  /** セッション選択時 */
  onSessionSelect?: (name: string) => void;
  /** ウィンドウ選択時 */
  onWindowSelect?: (index: number) => void;
  /** ペイン選択時 */
  onPaneSelect?: (index: number) => void;
  /** 新規接続追加ボタン押下時 */
  onAddConnection?: () => void;
  /** 設定ボタン押下時 */
  onSettingsPress?: () => void;
}

/**
 * 接続アイテム
 */
function ConnectionItem({
  connection,
  state,
  isActive,
  onPress,
}: {
  connection: Connection;
  state?: ConnectionState;
  isActive: boolean;
  onPress?: () => void;
}) {
  const isConnected = state?.status === 'connected';

  return (
    <Pressable
      style={[styles.connectionItem, isActive && styles.connectionItemActive]}
      onPress={onPress}
    >
      <MaterialCommunityIcons
        name="server"
        size={20}
        color={isConnected ? colors.primary : colors.textMuted}
      />
      <View style={styles.connectionInfo}>
        <Text style={styles.connectionName} numberOfLines={1}>
          {connection.name}
        </Text>
        <Text style={styles.connectionMeta} numberOfLines={1}>
          {isConnected ? `ssh • ${state?.latency ?? '-'}ms` : 'disconnected'}
        </Text>
      </View>
      {isConnected && <View style={styles.statusDot} />}
    </Pressable>
  );
}

/**
 * ペインアイテム
 */
function PaneItem({
  pane,
  isSelected,
  onPress,
}: {
  pane: TmuxPane;
  isSelected: boolean;
  onPress?: () => void;
}) {
  return (
    <Pressable
      style={[styles.paneItem, isSelected && styles.paneItemSelected]}
      onPress={onPress}
    >
      <MaterialCommunityIcons
        name={pane.active ? 'square-edit-outline' : 'file-document-outline'}
        size={16}
        color={isSelected ? colors.primary : colors.textMuted}
      />
      <Text
        style={[styles.paneText, isSelected && styles.paneTextSelected]}
        numberOfLines={1}
      >
        Pane {pane.index}
      </Text>
    </Pressable>
  );
}

/**
 * ウィンドウアイテム
 */
function WindowItem({
  window,
  isSelected,
  selectedPane,
  onWindowPress,
  onPanePress,
}: {
  window: TmuxWindow;
  isSelected: boolean;
  selectedPane?: number;
  onWindowPress?: () => void;
  onPanePress?: (index: number) => void;
}) {
  const iconName = window.name.includes('vim')
    ? 'code-tags'
    : window.name.includes('htop')
      ? 'chart-bar'
      : 'console';

  return (
    <View>
      <Pressable style={styles.windowItem} onPress={onWindowPress}>
        <MaterialCommunityIcons
          name={iconName}
          size={18}
          color={isSelected ? colors.text : colors.textMuted}
        />
        <Text
          style={[styles.windowText, isSelected && styles.windowTextSelected]}
          numberOfLines={1}
        >
          {window.index}: {window.name}
          {isSelected && ' (active)'}
        </Text>
      </Pressable>

      {/* ペイン一覧（選択中のウィンドウのみ表示） */}
      {isSelected && window.panes.length > 1 && (
        <View style={styles.panesContainer}>
          {window.panes.map((pane) => (
            <PaneItem
              key={pane.id}
              pane={pane}
              isSelected={selectedPane === pane.index}
              onPress={() => onPanePress?.(pane.index)}
            />
          ))}
        </View>
      )}
    </View>
  );
}

/**
 * セッションツリー
 */
function SessionTree({
  session,
  isSelected,
  selectedWindow,
  selectedPane,
  onSessionPress,
  onWindowPress,
  onPanePress,
}: {
  session: TmuxSession;
  isSelected: boolean;
  selectedWindow?: number;
  selectedPane?: number;
  onSessionPress?: () => void;
  onWindowPress?: (index: number) => void;
  onPanePress?: (index: number) => void;
}) {
  return (
    <View>
      {/* セッション名 */}
      <Pressable style={styles.sessionItem} onPress={onSessionPress}>
        <MaterialCommunityIcons
          name="dns"
          size={20}
          color={isSelected ? colors.primary : colors.textMuted}
        />
        <View style={styles.sessionInfo}>
          <Text
            style={[
              styles.sessionName,
              isSelected && styles.sessionNameSelected,
            ]}
            numberOfLines={1}
          >
            {session.name}
          </Text>
          <Text style={styles.sessionMeta}>
            {session.windows.length} windows
          </Text>
        </View>
      </Pressable>

      {/* ウィンドウツリー（選択中のセッションのみ） */}
      {isSelected && (
        <View style={styles.windowsContainer}>
          {session.windows.map((window) => (
            <WindowItem
              key={window.index}
              window={window}
              isSelected={selectedWindow === window.index}
              selectedPane={selectedPane}
              onWindowPress={() => onWindowPress?.(window.index)}
              onPanePress={onPanePress}
            />
          ))}
        </View>
      )}
    </View>
  );
}

export function Sidebar({
  connections,
  connectionStates,
  activeConnectionId,
  onConnectionPress,
  sessions,
  selectedSession,
  selectedWindow,
  selectedPane,
  onSessionSelect,
  onWindowSelect,
  onPaneSelect,
  onAddConnection,
  onSettingsPress,
}: SidebarProps) {
  // アクティブな接続
  const activeConnection = connections.find((c) => c.id === activeConnectionId);

  // 非アクティブな接続
  const inactiveConnections = connections.filter(
    (c) => c.id !== activeConnectionId
  );

  return (
    <View style={styles.container}>
      {/* ヘッダー */}
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <View style={styles.logoContainer}>
            <MaterialCommunityIcons
              name="console"
              size={20}
              color={colors.primary}
            />
          </View>
          <Text style={styles.title}>MuxPod</Text>
        </View>
        <Pressable onPress={onSettingsPress} style={styles.settingsButton}>
          <MaterialCommunityIcons
            name="cog"
            size={24}
            color={colors.textMuted}
          />
        </Pressable>
      </View>

      {/* コンテンツ */}
      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {/* アクティブセッション */}
        {activeConnection && (
          <>
            <Text style={styles.sectionLabel}>Active Session</Text>
            <ConnectionItem
              connection={activeConnection}
              state={connectionStates[activeConnection.id]}
              isActive={true}
              onPress={() => onConnectionPress?.(activeConnection)}
            />

            {/* tmuxセッションツリー */}
            {sessions && sessions.length > 0 && (
              <View style={styles.sessionsTree}>
                {sessions.map((session) => (
                  <SessionTree
                    key={session.name}
                    session={session}
                    isSelected={selectedSession === session.name}
                    selectedWindow={selectedWindow}
                    selectedPane={selectedPane}
                    onSessionPress={() => onSessionSelect?.(session.name)}
                    onWindowPress={onWindowSelect}
                    onPanePress={onPaneSelect}
                  />
                ))}
              </View>
            )}
          </>
        )}

        {/* 非アクティブ接続 */}
        {inactiveConnections.length > 0 && (
          <>
            <Text style={[styles.sectionLabel, styles.sectionLabelInactive]}>
              Inactive
            </Text>
            {inactiveConnections.map((connection) => (
              <ConnectionItem
                key={connection.id}
                connection={connection}
                state={connectionStates[connection.id]}
                isActive={false}
                onPress={() => onConnectionPress?.(connection)}
              />
            ))}
          </>
        )}

        {/* 接続がない場合 */}
        {connections.length === 0 && (
          <View style={styles.emptyState}>
            <MaterialCommunityIcons
              name="access-point-network"
              size={48}
              color={colors.textMuted}
            />
            <Text style={styles.emptyText}>No connections</Text>
          </View>
        )}
      </ScrollView>

      {/* フッター */}
      <View style={styles.footer}>
        <Pressable style={styles.addButton} onPress={onAddConnection}>
          <MaterialCommunityIcons name="plus" size={20} color={colors.primary} />
          <Text style={styles.addButtonText}>New Session</Text>
        </Pressable>
        <Text style={styles.version}>v1.0.0</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: SIDEBAR_WIDTH,
    height: '100%',
    backgroundColor: '#18191a', // sidebar-dark
    borderRightWidth: 1,
    borderRightColor: colors.borderLight,
  },

  // Header
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md + 4, // px-5
    paddingVertical: spacing.lg, // py-6
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 4, // gap-3
  },
  logoContainer: {
    width: 32,
    height: 32,
    borderRadius: borderRadius.sm,
    backgroundColor: 'rgba(0, 192, 209, 0.2)', // primary/20
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: -0.5,
  },
  settingsButton: {
    padding: spacing.xs,
  },

  // Content
  content: {
    flex: 1,
    paddingHorizontal: spacing.sm + 4, // px-3
  },

  // Section Label
  sectionLabel: {
    fontSize: fontSize.xs,
    fontWeight: '500',
    color: colors.textMuted,
    textTransform: 'uppercase',
    letterSpacing: 1,
    paddingHorizontal: spacing.sm + 4,
    marginBottom: spacing.sm,
    marginTop: spacing.sm,
  },
  sectionLabelInactive: {
    marginTop: spacing.lg,
  },

  // Connection Item
  connectionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 4, // gap-3
    padding: spacing.sm + 4, // p-3
    borderRadius: borderRadius.lg,
  },
  connectionItemActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)', // hover:bg-white/5
  },
  connectionInfo: {
    flex: 1,
    minWidth: 0,
  },
  connectionName: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.text,
  },
  connectionMeta: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.success,
    shadowColor: colors.success,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 8,
  },

  // Sessions Tree
  sessionsTree: {
    paddingLeft: spacing.sm + 4, // pl-3
    marginTop: spacing.sm,
    borderLeftWidth: 2,
    borderLeftColor: colors.borderLight,
    marginLeft: spacing.lg, // ml-6
  },

  // Session Item
  sessionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 4,
    padding: spacing.sm,
    borderRadius: borderRadius.lg,
  },
  sessionInfo: {
    flex: 1,
    minWidth: 0,
  },
  sessionName: {
    fontSize: fontSize.md,
    fontWeight: '500',
    color: colors.textSecondary,
  },
  sessionNameSelected: {
    fontWeight: '700',
    color: colors.text,
  },
  sessionMeta: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },

  // Windows Container
  windowsContainer: {
    paddingLeft: spacing.md,
    marginTop: spacing.xs,
    marginLeft: spacing.md + 4, // ml-5
    borderLeftWidth: 1,
    borderLeftColor: colors.borderLight,
    gap: spacing.xs,
  },

  // Window Item
  windowItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 4,
    padding: spacing.sm,
    borderRadius: borderRadius.lg,
  },
  windowText: {
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  windowTextSelected: {
    color: colors.textSecondary,
    fontWeight: '500',
  },

  // Panes Container
  panesContainer: {
    paddingLeft: spacing.md,
    marginTop: spacing.xs,
    marginLeft: spacing.md + 4,
    borderLeftWidth: 1,
    borderLeftColor: colors.borderLight,
    gap: spacing.xs,
  },

  // Pane Item
  paneItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 4,
    padding: spacing.sm,
    borderRadius: borderRadius.md,
  },
  paneItemSelected: {
    backgroundColor: 'rgba(0, 192, 209, 0.1)', // primary/10
    borderRightWidth: 2,
    borderRightColor: colors.primary,
  },
  paneText: {
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  paneTextSelected: {
    color: colors.primary,
    fontWeight: '500',
  },

  // Empty State
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.xxl,
    gap: spacing.sm,
  },
  emptyText: {
    fontSize: fontSize.md,
    color: colors.textMuted,
  },

  // Footer
  footer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
    backgroundColor: '#18191a', // sidebar-dark
  },
  addButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  addButtonText: {
    fontSize: fontSize.md,
    fontWeight: '500',
    color: colors.primary,
  },
  version: {
    fontSize: fontSize.xs,
    color: colors.textDim,
    fontFamily: 'monospace',
  },
});
