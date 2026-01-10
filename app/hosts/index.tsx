/**
 * 既知ホスト管理画面
 *
 * 信頼済みホストの一覧表示と管理。
 */
import { useCallback, useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  ScrollView,
  RefreshControl,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { Stack, useRouter } from 'expo-router';

import { getAllHosts, deleteHost, clearAllHosts } from '@/services/ssh/knownHostManager';
import type { KnownHost } from '@/types/sshKey';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

/**
 * 日付をフォーマットする
 */
function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diffDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));

  if (diffDays === 0) {
    return 'Today';
  } else if (diffDays === 1) {
    return 'Yesterday';
  } else if (diffDays < 7) {
    return `${diffDays} days ago`;
  } else {
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: date.getFullYear() !== now.getFullYear() ? 'numeric' : undefined,
    });
  }
}

interface HostCardProps {
  host: KnownHost;
  onDelete: () => void;
}

function HostCard({ host, onDelete }: HostCardProps) {
  const handleDelete = useCallback(() => {
    Alert.alert(
      'Remove Host',
      `Are you sure you want to remove ${host.host}:${host.port} from trusted hosts?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: onDelete,
        },
      ]
    );
  }, [host, onDelete]);

  return (
    <View style={styles.hostCard}>
      <View style={styles.hostCardHeader}>
        <View style={styles.hostIconContainer}>
          <MaterialCommunityIcons
            name="server"
            size={20}
            color={colors.primary}
          />
        </View>
        <View style={styles.hostInfo}>
          <Text style={styles.hostAddress} numberOfLines={1}>
            {host.host}:{host.port}
          </Text>
          <View style={styles.hostMeta}>
            <View style={styles.keyTypeBadge}>
              <Text style={styles.keyTypeBadgeText}>{host.keyType}</Text>
            </View>
            <Text style={styles.hostDate}>Added {formatDate(host.addedAt)}</Text>
          </View>
        </View>
        <Pressable
          style={styles.deleteButton}
          onPress={handleDelete}
          hitSlop={8}
        >
          <MaterialCommunityIcons
            name="close"
            size={18}
            color={colors.textMuted}
          />
        </Pressable>
      </View>

      <View style={styles.fingerprintContainer}>
        <Text style={styles.fingerprintLabel}>FINGERPRINT</Text>
        <Text style={styles.fingerprintText} selectable numberOfLines={1}>
          {host.fingerprint}
        </Text>
      </View>

      {host.lastVerifiedAt !== host.addedAt && (
        <Text style={styles.lastVerified}>
          Last verified {formatDate(host.lastVerifiedAt)}
        </Text>
      )}
    </View>
  );
}

export default function KnownHostsScreen() {
  const router = useRouter();
  const [hosts, setHosts] = useState<KnownHost[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadHosts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const allHosts = await getAllHosts();
      setHosts(allHosts);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load hosts');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadHosts();
  }, [loadHosts]);

  const handleDeleteHost = useCallback(
    async (identifier: string) => {
      try {
        await deleteHost(identifier);
        setHosts((prev) => prev.filter((h) => h.identifier !== identifier));
      } catch (err) {
        Alert.alert(
          'Error',
          err instanceof Error ? err.message : 'Failed to remove host'
        );
      }
    },
    []
  );

  const handleClearAll = useCallback(() => {
    if (hosts.length === 0) return;

    Alert.alert(
      'Clear All Hosts',
      'Are you sure you want to remove all trusted hosts? You will need to verify each host again on next connection.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear All',
          style: 'destructive',
          onPress: async () => {
            try {
              await clearAllHosts();
              setHosts([]);
            } catch (err) {
              Alert.alert(
                'Error',
                err instanceof Error ? err.message : 'Failed to clear hosts'
              );
            }
          },
        },
      ]
    );
  }, [hosts.length]);

  const renderEmptyState = () => (
    <View style={styles.emptyState}>
      <View style={styles.emptyIconContainer}>
        <MaterialCommunityIcons
          name="server-security"
          size={64}
          color={colors.textMuted}
        />
      </View>
      <Text style={styles.emptyTitle}>No Known Hosts</Text>
      <Text style={styles.emptySubtitle}>
        When you connect to a server for the first time and trust its host key,
        it will appear here.
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      <Stack.Screen
        options={{
          title: 'Known Hosts',
          headerShown: false,
        }}
      />

      {/* Header */}
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} style={styles.headerButton}>
          <MaterialCommunityIcons
            name="arrow-left"
            size={24}
            color={colors.text}
          />
        </Pressable>
        <Text style={styles.headerTitle}>Known Hosts</Text>
        {hosts.length > 0 ? (
          <Pressable onPress={handleClearAll} style={styles.headerButton}>
            <MaterialCommunityIcons
              name="delete-outline"
              size={24}
              color={colors.error}
            />
          </Pressable>
        ) : (
          <View style={styles.headerButton} />
        )}
      </View>

      {/* Error Banner */}
      {error && (
        <View style={styles.errorBanner}>
          <MaterialCommunityIcons
            name="alert-circle"
            size={20}
            color={colors.error}
          />
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      {/* Content */}
      {hosts.length === 0 && !loading ? (
        renderEmptyState()
      ) : (
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
          refreshControl={
            <RefreshControl
              refreshing={loading}
              onRefresh={loadHosts}
              tintColor={colors.primary}
              colors={[colors.primary]}
            />
          }
        >
          {/* Info Box */}
          <View style={styles.infoBox}>
            <MaterialCommunityIcons
              name="shield-check"
              size={20}
              color={colors.primary}
            />
            <Text style={styles.infoText}>
              These hosts have been verified and trusted. Their fingerprints are stored
              to detect any changes that might indicate a security issue.
            </Text>
          </View>

          {/* Hosts List */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>
              TRUSTED HOSTS ({hosts.length})
            </Text>
            <View style={styles.hostsList}>
              {hosts.map((host) => (
                <HostCard
                  key={host.identifier}
                  host={host}
                  onDelete={() => handleDeleteHost(host.identifier)}
                />
              ))}
            </View>
          </View>
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

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
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerTitle: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: -0.3,
  },
  errorBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.errorBadgeBg,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
  },
  errorText: {
    flex: 1,
    fontSize: fontSize.sm,
    color: colors.error,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: spacing.md,
    paddingBottom: spacing.xxl,
  },
  // Empty State
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.xl,
  },
  emptyIconContainer: {
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.lg,
  },
  emptyTitle: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.text,
    marginBottom: spacing.sm,
  },
  emptySubtitle: {
    fontSize: fontSize.md,
    color: colors.textSecondary,
    textAlign: 'center',
    paddingHorizontal: spacing.lg,
    lineHeight: 22,
  },
  // Info Box
  infoBox: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    backgroundColor: 'rgba(0, 192, 209, 0.05)',
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    gap: spacing.sm,
    borderWidth: 1,
    borderColor: 'rgba(0, 192, 209, 0.1)',
    marginBottom: spacing.lg,
  },
  infoText: {
    flex: 1,
    fontSize: fontSize.sm,
    color: colors.textSecondary,
    lineHeight: 20,
  },
  // Section
  section: {
    marginBottom: spacing.lg,
  },
  sectionTitle: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    letterSpacing: 1.5,
    color: colors.textMuted,
    textTransform: 'uppercase',
    marginBottom: spacing.md,
    paddingHorizontal: spacing.xs,
  },
  hostsList: {
    gap: spacing.md,
  },
  // Host Card
  hostCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  hostCardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    marginBottom: spacing.md,
  },
  hostIconContainer: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  hostInfo: {
    flex: 1,
  },
  hostAddress: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
    fontFamily: 'monospace',
    marginBottom: 4,
  },
  hostMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  keyTypeBadge: {
    backgroundColor: colors.surfaceHighlight,
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
  },
  keyTypeBadgeText: {
    fontSize: fontSize.xxs,
    fontWeight: '700',
    color: colors.textMuted,
    letterSpacing: 0.5,
  },
  hostDate: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
  deleteButton: {
    width: 32,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 16,
  },
  fingerprintContainer: {
    backgroundColor: colors.background,
    borderRadius: borderRadius.lg,
    padding: spacing.sm,
  },
  fingerprintLabel: {
    fontSize: fontSize.xxs,
    fontWeight: '700',
    letterSpacing: 0.5,
    color: colors.textMuted,
    marginBottom: 4,
  },
  fingerprintText: {
    fontSize: fontSize.xs,
    color: colors.text,
    fontFamily: 'monospace',
  },
  lastVerified: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    marginTop: spacing.sm,
    textAlign: 'right',
  },
});
