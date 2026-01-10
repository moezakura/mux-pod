/**
 * ConnectionCard
 *
 * 展開可能な接続カードコンポーネント。
 * HTMLデザイン (server_connections_list.html) に完全準拠。
 */
import { memo, useCallback, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  StyleSheet,
  type GestureResponderEvent,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import type { Connection, ConnectionState } from '@/types/connection';
import type { TmuxSession } from '@/types/tmux';
import { colors, borderRadius, spacing, fontSize, shadows } from '@/theme';

export interface ConnectionCardProps {
  /** 接続設定 */
  connection: Connection;
  /** 接続状態 */
  state?: ConnectionState;
  /** セッション一覧 */
  sessions?: TmuxSession[];
  /** タップ時のコールバック */
  onPress?: () => void;
  /** 長押し時のコールバック */
  onLongPress?: (event: GestureResponderEvent) => void;
  /** セッション選択時のコールバック */
  onSelectSession?: (session: TmuxSession) => void;
}

/**
 * サーバーアイコン（ステータスドット付き）
 */
const ServerIcon = memo(function ServerIcon({
  connected,
  status,
}: {
  connected: boolean;
  status?: ConnectionState['status'];
}) {
  // ステータスドットの色
  let dotColor: string = colors.error;
  let dotShadow = {};
  if (status === 'connected') {
    dotColor = colors.success;
    dotShadow = shadows.statusDot;
  } else if (status === 'connecting') {
    dotColor = colors.warning;
  }

  return (
    <View style={styles.iconWrapper}>
      <View
        style={[
          styles.iconContainer,
          connected && styles.iconContainerActive,
        ]}
      >
        <MaterialCommunityIcons
          name="dns"
          size={20}
          color={connected ? colors.primary : colors.textSecondary}
        />
      </View>
      {status && (
        <View style={[styles.statusDot, { backgroundColor: dotColor }, dotShadow]} />
      )}
    </View>
  );
});

/**
 * セッションバッジ
 */
const SessionBadge = memo(function SessionBadge({ attached }: { attached: boolean }) {
  return (
    <View style={[styles.badge, attached ? styles.badgeAttached : styles.badgeDetached]}>
      <Text style={[styles.badgeText, attached ? styles.badgeTextAttached : styles.badgeTextDetached]}>
        {attached ? 'Attached' : 'Detached'}
      </Text>
    </View>
  );
});

/**
 * セッションアイテム
 */
const SessionItem = memo(function SessionItem({
  session,
  onPress,
}: {
  session: TmuxSession;
  onPress?: () => void;
}) {
  const windowCount = session.windows.length;
  return (
    <Pressable
      style={({ pressed }) => [
        styles.sessionItem,
        pressed && styles.sessionItemPressed,
      ]}
      onPress={onPress}
    >
      <View style={styles.sessionLeft}>
        <MaterialCommunityIcons
          name="console"
          size={14}
          color={session.attached ? colors.primary : colors.textMuted}
        />
        <View style={styles.sessionInfo}>
          <Text style={styles.sessionName}>{session.name}</Text>
          <Text style={styles.sessionMeta}>
            {windowCount} window{windowCount !== 1 ? 's' : ''}
          </Text>
        </View>
      </View>
      <SessionBadge attached={session.attached} />
    </Pressable>
  );
});

/**
 * ConnectionCard
 */
export const ConnectionCard = memo(function ConnectionCard({
  connection,
  state,
  sessions = [],
  onPress,
  onLongPress,
  onSelectSession,
}: ConnectionCardProps) {
  const [expanded, setExpanded] = useState(false);
  const isConnected = state?.status === 'connected';
  const isDisconnected = state?.status === 'disconnected' || state?.status === 'error';

  const handlePress = useCallback(() => {
    if (sessions.length > 0 || isConnected) {
      setExpanded((prev) => !prev);
    }
    onPress?.();
  }, [sessions.length, isConnected, onPress]);

  const handleSessionPress = useCallback(
    (session: TmuxSession) => {
      onSelectSession?.(session);
    },
    [onSelectSession]
  );

  return (
    <View style={[styles.card, isDisconnected && styles.cardDisconnected]}>
      <Pressable
        style={({ pressed }) => [
          styles.cardHeader,
          pressed && styles.cardHeaderPressed,
        ]}
        onPress={handlePress}
        onLongPress={onLongPress}
        delayLongPress={500}
        testID="connection-card"
      >
        <ServerIcon connected={isConnected} status={state?.status} />

        <View style={styles.cardContent}>
          <Text
            style={[styles.connectionName, isDisconnected && styles.connectionNameDisabled]}
            numberOfLines={1}
          >
            {connection.name}
          </Text>
          <Text style={styles.connectionMeta} numberOfLines={1}>
            {connection.host}
            <Text style={styles.metaSeparator}> • </Text>
            {connection.username || 'user'}
          </Text>
        </View>

        <MaterialCommunityIcons
          name={expanded ? 'chevron-up' : 'chevron-down'}
          size={24}
          color={isDisconnected ? colors.textDim : colors.textMuted}
        />
      </Pressable>

      {expanded && sessions.length > 0 && (
        <View style={styles.sessionsContainer}>
          <View style={styles.sessionsContent}>
            <Text style={styles.sessionsTitle}>Active Sessions</Text>
            {sessions.map((session) => (
              <SessionItem
                key={session.name}
                session={session}
                onPress={() => handleSessionPress(session)}
              />
            ))}
            <Pressable style={styles.newSessionButton}>
              <MaterialCommunityIcons name="plus" size={14} color={colors.primary} />
              <Text style={styles.newSessionText}>New Session</Text>
            </Pressable>
          </View>
        </View>
      )}

      {state?.error && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorText} numberOfLines={2}>
            {state.error}
          </Text>
        </View>
      )}
    </View>
  );
});

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    marginHorizontal: spacing.md,
    marginVertical: spacing.xs,
    overflow: 'hidden',
    ...shadows.card,
  },
  cardDisconnected: {
    opacity: 0.8,
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.md,
  },
  cardHeaderPressed: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  iconWrapper: {
    position: 'relative',
    marginRight: spacing.md,
  },
  iconContainer: {
    width: 40,
    height: 40,
    borderRadius: borderRadius.lg,
    backgroundColor: colors.surfaceHighlight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  iconContainerActive: {
    backgroundColor: colors.serverIconBg,
    borderWidth: 1,
    borderColor: colors.serverIconBorder,
  },
  statusDot: {
    position: 'absolute',
    top: -4,
    right: -4,
    width: 10,
    height: 10,
    borderRadius: 5,
    borderWidth: 2,
    borderColor: colors.surface,
  },
  cardContent: {
    flex: 1,
    marginRight: spacing.sm,
  },
  connectionName: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: 0.3,
  },
  connectionNameDisabled: {
    color: colors.textSecondary,
    fontWeight: '500',
  },
  connectionMeta: {
    fontSize: fontSize.sm,
    fontFamily: 'monospace',
    color: colors.textSecondary,
    marginTop: 2,
    letterSpacing: -0.3,
  },
  metaSeparator: {
    color: colors.textDim,
  },
  sessionsContainer: {
    backgroundColor: colors.expandedBg,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  sessionsContent: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  sessionsTitle: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textMuted,
    textTransform: 'uppercase',
    letterSpacing: 1.5,
    marginTop: spacing.sm,
    marginBottom: spacing.sm,
    marginLeft: spacing.sm,
  },
  sessionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: spacing.sm,
    borderRadius: borderRadius.sm,
    marginBottom: 4,
  },
  sessionItemPressed: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  sessionLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  sessionInfo: {
    gap: 2,
  },
  sessionName: {
    fontSize: fontSize.md,
    fontWeight: '500',
    color: colors.textSecondary,
  },
  sessionMeta: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  badge: {
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
    borderWidth: 1,
  },
  badgeAttached: {
    backgroundColor: colors.badgeAttachedBg,
    borderColor: colors.badgeAttachedBorder,
  },
  badgeDetached: {
    backgroundColor: colors.badgeDetachedBg,
    borderColor: colors.badgeDetachedBorder,
  },
  badgeText: {
    fontSize: fontSize.xs,
    fontWeight: '500',
  },
  badgeTextAttached: {
    color: colors.badgeAttachedText,
  },
  badgeTextDetached: {
    color: colors.badgeDetachedText,
  },
  newSessionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.sm,
    marginTop: spacing.sm,
    marginBottom: spacing.sm,
    borderWidth: 1,
    borderColor: 'rgba(0, 192, 209, 0.2)',
    borderRadius: borderRadius.sm,
    borderStyle: 'dashed',
    gap: spacing.sm,
  },
  newSessionText: {
    fontSize: fontSize.sm,
    color: 'rgba(0, 192, 209, 0.8)',
    fontWeight: '500',
  },
  errorContainer: {
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.md,
    paddingTop: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  errorText: {
    fontSize: fontSize.sm,
    color: colors.error,
  },
});
