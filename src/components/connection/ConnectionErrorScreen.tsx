/**
 * ConnectionErrorScreen
 *
 * 接続エラー状態を表示するフルスクリーンコンポーネント。
 * HTMLデザイン (connection_error_state.html) に完全準拠。
 */
import { memo, useState, useCallback } from 'react';
import {
  View,
  Text,
  Pressable,
  StyleSheet,
  ScrollView,
  Animated,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import {
  colors,
  borderRadius,
  spacing,
  fontSize,
  shadows,
} from '@/theme/tokens';

/** ログエントリの型 */
export interface LogEntry {
  timestamp: string;
  message: string;
  level: 'info' | 'warning' | 'error';
}

export interface ConnectionErrorScreenProps {
  /** エラータイトル */
  title?: string;
  /** ホスト名/IP */
  host: string;
  /** エラー詳細メッセージ */
  message?: string;
  /** 終了コード */
  exitCode?: number;
  /** ログエントリ */
  logs?: LogEntry[];
  /** 閉じるボタン押下時 */
  onClose?: () => void;
  /** リトライボタン押下時 */
  onRetry?: () => void;
  /** ホスト変更ボタン押下時 */
  onChangeHost?: () => void;
  /** 設定ボタン押下時 */
  onSettings?: () => void;
  /** メニューボタン押下時 */
  onMenu?: () => void;
}

/**
 * ステータスバッジ（Disconnected）
 */
const StatusBadge = memo(function StatusBadge() {
  return (
    <View style={styles.statusBadge}>
      <View style={styles.statusDot} />
      <Text style={styles.statusText}>Disconnected</Text>
    </View>
  );
});

/**
 * ログビューア
 */
const LogViewer = memo(function LogViewer({
  logs,
  exitCode,
}: {
  logs: LogEntry[];
  exitCode?: number;
}) {
  const [expanded, setExpanded] = useState(false);

  const toggleExpanded = useCallback(() => {
    setExpanded((prev) => !prev);
  }, []);

  // 最新のエラーログを取得
  const latestError = logs.find((log) => log.level === 'error');
  const otherLogs = logs.filter((log) => log !== latestError);

  const getLogColor = (level: LogEntry['level']) => {
    switch (level) {
      case 'error':
        return colors.error;
      case 'warning':
        return colors.warning;
      default:
        return colors.textSecondary;
    }
  };

  return (
    <View style={styles.logSection}>
      <View style={styles.logHeader}>
        <Text style={styles.logLabel}>System Log</Text>
        {exitCode !== undefined && (
          <View style={styles.exitCodeBadge}>
            <Text style={styles.exitCodeText}>exit code: {exitCode}</Text>
          </View>
        )}
      </View>
      <View style={styles.logContainer}>
        <View style={styles.logAccentBar} />
        <View style={styles.logContent}>
          {/* 最新エラー（常に表示） */}
          {latestError && (
            <View style={styles.logEntry}>
              <Text style={styles.logTimestamp}>{latestError.timestamp}</Text>
              <Text style={[styles.logMessage, { color: getLogColor(latestError.level) }]}>
                &gt; {latestError.message}
              </Text>
            </View>
          )}

          {/* 展開時に他のログを表示 */}
          {expanded &&
            otherLogs.map((log, index) => (
              <View key={index} style={styles.logEntry}>
                <Text style={styles.logTimestamp}>{log.timestamp}</Text>
                <Text style={[styles.logMessage, { color: getLogColor(log.level) }]}>
                  &gt; {log.message}
                </Text>
              </View>
            ))}

          {/* 展開/折りたたみボタン */}
          {otherLogs.length > 0 && (
            <Pressable style={styles.expandButton} onPress={toggleExpanded}>
              <Text style={styles.expandButtonText}>
                {expanded ? 'Hide Full Log' : 'View Full Log'}
              </Text>
              <MaterialCommunityIcons
                name={expanded ? 'chevron-up' : 'chevron-down'}
                size={14}
                color={colors.primary}
              />
            </Pressable>
          )}
        </View>
      </View>
    </View>
  );
});

/**
 * アクションアイテム
 */
const ActionItem = memo(function ActionItem({
  icon,
  title,
  subtitle,
  onPress,
}: {
  icon: keyof typeof MaterialCommunityIcons.glyphMap;
  title: string;
  subtitle: string;
  onPress?: () => void;
}) {
  return (
    <Pressable
      style={({ pressed }) => [
        styles.actionItem,
        pressed && styles.actionItemPressed,
      ]}
      onPress={onPress}
    >
      <View style={styles.actionIconContainer}>
        <MaterialCommunityIcons
          name={icon}
          size={20}
          color={colors.textMuted}
        />
      </View>
      <View style={styles.actionContent}>
        <Text style={styles.actionTitle}>{title}</Text>
        <Text style={styles.actionSubtitle}>{subtitle}</Text>
      </View>
      <MaterialCommunityIcons
        name="chevron-right"
        size={20}
        color={colors.textDim}
      />
    </Pressable>
  );
});

/**
 * ConnectionErrorScreen
 */
export const ConnectionErrorScreen = memo(function ConnectionErrorScreen({
  title = 'Connection Timeout',
  host,
  message,
  exitCode = 1,
  logs = [],
  onClose,
  onRetry,
  onChangeHost,
  onSettings,
  onMenu,
}: ConnectionErrorScreenProps) {
  const defaultMessage = `Could not reach host ${host}. The server is taking too long to respond.`;
  const displayMessage = message || defaultMessage;

  const defaultLogs: LogEntry[] = logs.length > 0 ? logs : [
    { timestamp: '00:30', message: 'Critical: Timeout waiting for remote host.', level: 'error' },
    { timestamp: '00:01', message: 'Initializing connection...', level: 'info' },
    { timestamp: '00:02', message: `Handshake sent to ${host}:22`, level: 'info' },
    { timestamp: '00:05', message: 'Warning: Response latency high (450ms)', level: 'warning' },
    { timestamp: '00:15', message: 'Retrying (attempt 1/3)...', level: 'info' },
  ];

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Pressable
          style={({ pressed }) => [
            styles.headerButton,
            pressed && styles.headerButtonPressed,
          ]}
          onPress={onClose}
        >
          <MaterialCommunityIcons name="close" size={24} color={colors.text} />
        </Pressable>

        <StatusBadge />

        <Pressable
          style={({ pressed }) => [
            styles.headerButton,
            pressed && styles.headerButtonPressed,
          ]}
          onPress={onMenu}
        >
          <MaterialCommunityIcons
            name="dots-vertical"
            size={24}
            color={colors.text}
          />
        </Pressable>
      </View>

      {/* Content */}
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Title Section */}
        <View style={styles.titleSection}>
          <Text style={styles.title}>{title}</Text>
          <Text style={styles.description}>
            Could not reach host{' '}
            <Text style={styles.hostText}>{host}</Text>
            . The server is taking too long to respond.
          </Text>
        </View>

        {/* Retry Button */}
        <Pressable
          style={({ pressed }) => [
            styles.retryButton,
            pressed && styles.retryButtonPressed,
          ]}
          onPress={onRetry}
        >
          <MaterialCommunityIcons name="refresh" size={20} color="#000000" />
          <Text style={styles.retryButtonText}>Retry Connection</Text>
        </Pressable>

        {/* Log Viewer */}
        <LogViewer logs={defaultLogs} exitCode={exitCode} />

        {/* Action List */}
        <View style={styles.actionList}>
          <ActionItem
            icon="dns"
            title="Change Host"
            subtitle="Connect to a different server"
            onPress={onChangeHost}
          />
          <View style={styles.actionDivider} />
          <ActionItem
            icon="ethernet"
            title="Connection Settings"
            subtitle="Configure timeouts and proxies"
            onPress={onSettings}
          />
        </View>
      </ScrollView>
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  headerButton: {
    width: 40,
    height: 40,
    borderRadius: borderRadius.full,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerButtonPressed: {
    backgroundColor: colors.borderLight,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: colors.errorBadgeBg,
    borderWidth: 1,
    borderColor: colors.errorBadgeBorder,
    paddingHorizontal: spacing.sm + 4,
    paddingVertical: spacing.xs,
    borderRadius: borderRadius.full,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.error,
  },
  statusText: {
    fontSize: fontSize.sm,
    fontWeight: '700',
    color: colors.error,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: spacing.md,
    paddingBottom: spacing.xl,
    gap: spacing.lg,
  },
  titleSection: {
    alignItems: 'center',
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
    gap: spacing.sm,
  },
  title: {
    fontSize: 30,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: -0.5,
    textAlign: 'center',
  },
  description: {
    fontSize: fontSize.lg,
    color: colors.textSecondary,
    textAlign: 'center',
    lineHeight: 24,
    maxWidth: '90%',
  },
  hostText: {
    fontFamily: 'monospace',
    backgroundColor: colors.borderLight,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
    fontSize: fontSize.md,
    color: colors.textSecondary,
    overflow: 'hidden',
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.xl,
    ...shadows.glow,
  },
  retryButtonPressed: {
    opacity: 0.9,
    transform: [{ scale: 0.98 }],
  },
  retryButtonText: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: '#000000',
  },
  logSection: {
    gap: spacing.sm,
  },
  logHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.xs,
  },
  logLabel: {
    fontSize: fontSize.sm,
    fontWeight: '700',
    color: colors.textMuted,
    textTransform: 'uppercase',
    letterSpacing: 1.5,
  },
  exitCodeBadge: {
    backgroundColor: colors.errorBadgeBg,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
  },
  exitCodeText: {
    fontSize: fontSize.xs,
    fontFamily: 'monospace',
    color: colors.errorLight,
  },
  logContainer: {
    backgroundColor: colors.logBg,
    borderRadius: borderRadius.lg,
    borderWidth: 1,
    borderColor: colors.logBorder,
    overflow: 'hidden',
    flexDirection: 'row',
  },
  logAccentBar: {
    width: 4,
    backgroundColor: colors.errorAccent,
  },
  logContent: {
    flex: 1,
    padding: spacing.md,
    gap: spacing.sm,
  },
  logEntry: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  logTimestamp: {
    fontSize: fontSize.sm,
    fontFamily: 'monospace',
    color: colors.logTimestamp,
    minWidth: 40,
  },
  logMessage: {
    flex: 1,
    fontSize: fontSize.sm,
    fontFamily: 'monospace',
    fontWeight: '700',
  },
  expandButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    marginTop: spacing.sm,
  },
  expandButtonText: {
    fontSize: fontSize.sm,
    color: colors.primary,
  },
  actionList: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    borderWidth: 1,
    borderColor: colors.borderLight,
    overflow: 'hidden',
    marginTop: spacing.sm,
  },
  actionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.md,
  },
  actionItemPressed: {
    backgroundColor: colors.borderLight,
  },
  actionIconContainer: {
    width: 36,
    height: 36,
    borderRadius: borderRadius.lg,
    backgroundColor: colors.borderLight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  actionContent: {
    flex: 1,
    gap: 2,
  },
  actionTitle: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
  },
  actionSubtitle: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  actionDivider: {
    height: 1,
    backgroundColor: colors.borderLight,
  },
});
