/**
 * SSH鍵一覧画面
 *
 * 保存されている鍵の一覧を表示し、生成/インポート/詳細への導線を提供。
 */
import { useCallback, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  ScrollView,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { Stack, useRouter } from 'expo-router';

import { getAllKeys } from '@/services/ssh/keyManager';
import { useKeyStore } from '@/stores/keyStore';
import { KeyCard } from '@/components/connection/KeyCard';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

export default function KeysListScreen() {
  const router = useRouter();
  const { keys, setKeys, isLoading, setLoading, error, setError } = useKeyStore();

  const loadKeys = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const allKeys = await getAllKeys();
      setKeys(allKeys);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load keys');
    } finally {
      setLoading(false);
    }
  }, [setKeys, setLoading, setError]);

  useEffect(() => {
    loadKeys();
  }, [loadKeys]);

  const handleGenerate = useCallback(() => {
    router.push('/keys/generate');
  }, [router]);

  const handleImport = useCallback(() => {
    router.push('/keys/import');
  }, [router]);

  const handleKeyPress = useCallback(
    (keyId: string) => {
      router.push(`/keys/${keyId}`);
    },
    [router]
  );

  const renderEmptyState = () => (
    <View style={styles.emptyState}>
      <View style={styles.emptyIconContainer}>
        <MaterialCommunityIcons
          name="key-outline"
          size={64}
          color={colors.textMuted}
        />
      </View>
      <Text style={styles.emptyTitle}>No SSH Keys</Text>
      <Text style={styles.emptySubtitle}>
        Generate a new key or import an existing one to get started.
      </Text>

      <View style={styles.emptyActions}>
        <Pressable
          style={({ pressed }) => [
            styles.emptyActionButton,
            styles.generateButton,
            pressed && styles.buttonPressed,
          ]}
          onPress={handleGenerate}
        >
          <MaterialCommunityIcons
            name="key-plus"
            size={20}
            color={colors.background}
          />
          <Text style={styles.generateButtonText}>Generate Key</Text>
        </Pressable>

        <Pressable
          style={({ pressed }) => [
            styles.emptyActionButton,
            styles.importButton,
            pressed && styles.buttonPressed,
          ]}
          onPress={handleImport}
        >
          <MaterialCommunityIcons
            name="key-arrow-right"
            size={20}
            color={colors.primary}
          />
          <Text style={styles.importButtonText}>Import Key</Text>
        </Pressable>
      </View>
    </View>
  );

  const renderKeyList = () => (
    <ScrollView
      style={styles.scrollView}
      contentContainerStyle={styles.scrollContent}
      showsVerticalScrollIndicator={false}
      refreshControl={
        <RefreshControl
          refreshing={isLoading}
          onRefresh={loadKeys}
          tintColor={colors.primary}
          colors={[colors.primary]}
        />
      }
    >
      {/* Quick Actions */}
      <View style={styles.quickActions}>
        <Pressable
          style={({ pressed }) => [
            styles.quickAction,
            pressed && styles.quickActionPressed,
          ]}
          onPress={handleGenerate}
        >
          <View style={styles.quickActionIcon}>
            <MaterialCommunityIcons
              name="key-plus"
              size={20}
              color={colors.primary}
            />
          </View>
          <Text style={styles.quickActionText}>Generate</Text>
        </Pressable>

        <Pressable
          style={({ pressed }) => [
            styles.quickAction,
            pressed && styles.quickActionPressed,
          ]}
          onPress={handleImport}
        >
          <View style={styles.quickActionIcon}>
            <MaterialCommunityIcons
              name="key-arrow-right"
              size={20}
              color={colors.primary}
            />
          </View>
          <Text style={styles.quickActionText}>Import</Text>
        </Pressable>
      </View>

      {/* Keys Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>
          YOUR KEYS ({keys.length})
        </Text>

        <View style={styles.keysList}>
          {keys.map((key) => (
            <KeyCard
              key={key.id}
              sshKey={key}
              onPress={() => handleKeyPress(key.id)}
            />
          ))}
        </View>
      </View>
    </ScrollView>
  );

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      <Stack.Screen
        options={{
          title: 'SSH Keys',
          headerShown: false,
        }}
      />

      {/* Header */}
      <View style={styles.header}>
        <Pressable
          onPress={() => router.back()}
          style={styles.headerButton}
        >
          <MaterialCommunityIcons
            name="arrow-left"
            size={24}
            color={colors.text}
          />
        </Pressable>
        <Text style={styles.headerTitle}>SSH Keys</Text>
        <View style={styles.headerButton} />
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
      {keys.length === 0 && !isLoading ? renderEmptyState() : renderKeyList()}
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
    marginBottom: spacing.xl,
    paddingHorizontal: spacing.lg,
  },
  emptyActions: {
    width: '100%',
    gap: spacing.md,
  },
  emptyActionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.md,
    borderRadius: borderRadius.xl,
    gap: spacing.sm,
  },
  generateButton: {
    backgroundColor: colors.primary,
  },
  generateButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.background,
  },
  importButton: {
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: colors.primary,
  },
  importButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.primary,
  },
  buttonPressed: {
    opacity: 0.8,
    transform: [{ scale: 0.98 }],
  },
  // Quick Actions
  quickActions: {
    flexDirection: 'row',
    gap: spacing.md,
    marginBottom: spacing.lg,
  },
  quickAction: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surface,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    gap: spacing.sm,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  quickActionPressed: {
    backgroundColor: colors.surfaceHighlight,
  },
  quickActionIcon: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  quickActionText: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
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
  keysList: {
    gap: spacing.md,
  },
});
