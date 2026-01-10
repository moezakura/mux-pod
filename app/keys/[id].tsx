/**
 * SSH鍵詳細画面
 *
 * 鍵の詳細情報を表示し、公開鍵のコピーや削除を行う。
 */
import { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  ScrollView,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { Stack, useRouter, useLocalSearchParams } from 'expo-router';
import * as Clipboard from 'expo-clipboard';

import { getKeyById, deleteKey } from '@/services/ssh/keyManager';
import { useKeyStore } from '@/stores/keyStore';
import type { SSHKey } from '@/types/sshKey';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

/**
 * 日付をフォーマットする
 */
function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/**
 * 鍵タイプの表示名を取得
 */
function getKeyTypeLabel(keyType: string): string {
  switch (keyType) {
    case 'ed25519':
      return 'ED25519';
    case 'rsa-2048':
      return 'RSA 2048';
    case 'rsa-4096':
      return 'RSA 4096';
    case 'ecdsa':
      return 'ECDSA (P-256)';
    default:
      return keyType.toUpperCase();
  }
}

export default function KeyDetailScreen() {
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();
  const removeKey = useKeyStore((state) => state.removeKey);

  const [sshKey, setSSHKey] = useState<SSHKey | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    const loadKey = async () => {
      if (!id) {
        setError('Key ID not found');
        setLoading(false);
        return;
      }

      try {
        const key = await getKeyById(id);
        if (!key) {
          setError('Key not found');
        } else {
          setSSHKey(key);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load key');
      } finally {
        setLoading(false);
      }
    };

    loadKey();
  }, [id]);

  const handleCopyPublicKey = useCallback(async () => {
    if (!sshKey) return;

    await Clipboard.setStringAsync(sshKey.publicKey);
    setCopied(true);

    setTimeout(() => {
      setCopied(false);
    }, 2000);
  }, [sshKey]);

  const handleDelete = useCallback(() => {
    if (!sshKey) return;

    Alert.alert(
      'Delete Key',
      `Are you sure you want to delete "${sshKey.name}"? This action cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            setDeleting(true);
            try {
              await deleteKey(sshKey.id);
              removeKey(sshKey.id);
              router.back();
            } catch (err) {
              Alert.alert(
                'Error',
                err instanceof Error ? err.message : 'Failed to delete key'
              );
            } finally {
              setDeleting(false);
            }
          },
        },
      ]
    );
  }, [sshKey, removeKey, router]);

  if (loading) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.loadingContainer}>
          <Text style={styles.loadingText}>Loading...</Text>
        </View>
      </SafeAreaView>
    );
  }

  if (error || !sshKey) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Pressable onPress={() => router.back()} style={styles.headerButton}>
            <MaterialCommunityIcons
              name="arrow-left"
              size={24}
              color={colors.text}
            />
          </Pressable>
          <Text style={styles.headerTitle}>Key Details</Text>
          <View style={styles.headerButton} />
        </View>
        <View style={styles.errorContainer}>
          <MaterialCommunityIcons
            name="alert-circle"
            size={48}
            color={colors.error}
          />
          <Text style={styles.errorTitle}>Key Not Found</Text>
          <Text style={styles.errorSubtitle}>
            {error ?? 'The requested key could not be found.'}
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      <Stack.Screen
        options={{
          title: 'Key Details',
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
        <Text style={styles.headerTitle}>Key Details</Text>
        <View style={styles.headerButton} />
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Key Header */}
        <View style={styles.keyHeader}>
          <View style={styles.keyIconContainer}>
            <MaterialCommunityIcons
              name="key-variant"
              size={32}
              color={colors.primary}
            />
          </View>
          <Text style={styles.keyName}>{sshKey.name}</Text>
          <View style={styles.keyBadges}>
            <View style={styles.typeBadge}>
              <Text style={styles.typeBadgeText}>
                {getKeyTypeLabel(sshKey.keyType)}
              </Text>
            </View>
            {sshKey.imported && (
              <View style={styles.importedBadge}>
                <Text style={styles.importedBadgeText}>Imported</Text>
              </View>
            )}
            {sshKey.requireBiometrics && (
              <View style={styles.biometricBadge}>
                <MaterialCommunityIcons
                  name="fingerprint"
                  size={12}
                  color={colors.primary}
                />
                <Text style={styles.biometricBadgeText}>Biometric</Text>
              </View>
            )}
          </View>
        </View>

        {/* Details Card */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>DETAILS</Text>
          <View style={styles.detailsCard}>
            <View style={styles.detailRow}>
              <Text style={styles.detailLabel}>Created</Text>
              <Text style={styles.detailValue}>{formatDate(sshKey.createdAt)}</Text>
            </View>
            <View style={styles.separator} />
            <View style={styles.detailRow}>
              <Text style={styles.detailLabel}>Fingerprint</Text>
              <Text style={[styles.detailValue, styles.monoText]} selectable>
                {sshKey.fingerprint}
              </Text>
            </View>
          </View>
        </View>

        {/* Public Key Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>PUBLIC KEY</Text>
          <View style={styles.publicKeyCard}>
            <Text style={styles.publicKeyText} selectable>
              {sshKey.publicKey}
            </Text>
          </View>
          <Pressable
            style={({ pressed }) => [
              styles.copyButton,
              copied && styles.copyButtonCopied,
              pressed && styles.copyButtonPressed,
            ]}
            onPress={handleCopyPublicKey}
          >
            <MaterialCommunityIcons
              name={copied ? 'check' : 'content-copy'}
              size={20}
              color={copied ? colors.success : colors.background}
            />
            <Text style={[styles.copyButtonText, copied && styles.copyButtonTextCopied]}>
              {copied ? 'Copied!' : 'Copy Public Key'}
            </Text>
          </Pressable>
        </View>

        {/* Usage Instructions */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>USAGE</Text>
          <View style={styles.usageCard}>
            <Text style={styles.usageTitle}>Add to your server</Text>
            <Text style={styles.usageDescription}>
              Append the public key above to your server&apos;s{' '}
              <Text style={styles.monoInline}>~/.ssh/authorized_keys</Text> file.
            </Text>
          </View>
        </View>

        {/* Danger Zone */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>DANGER ZONE</Text>
          <View style={styles.dangerCard}>
            <View style={styles.dangerInfo}>
              <MaterialCommunityIcons
                name="delete-outline"
                size={24}
                color={colors.error}
              />
              <View style={styles.dangerTextContainer}>
                <Text style={styles.dangerTitle}>Delete this key</Text>
                <Text style={styles.dangerDescription}>
                  Once deleted, you will no longer be able to connect using this key.
                </Text>
              </View>
            </View>
            <Pressable
              style={({ pressed }) => [
                styles.deleteButton,
                pressed && styles.deleteButtonPressed,
                deleting && styles.deleteButtonDisabled,
              ]}
              onPress={handleDelete}
              disabled={deleting}
            >
              <Text style={styles.deleteButtonText}>
                {deleting ? 'Deleting...' : 'Delete Key'}
              </Text>
            </Pressable>
          </View>
        </View>
      </ScrollView>
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
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  errorContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.xl,
  },
  errorTitle: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.text,
    marginTop: spacing.md,
    marginBottom: spacing.sm,
  },
  errorSubtitle: {
    fontSize: fontSize.md,
    color: colors.textSecondary,
    textAlign: 'center',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: spacing.md,
    paddingBottom: spacing.xxl,
  },
  // Key Header
  keyHeader: {
    alignItems: 'center',
    paddingVertical: spacing.lg,
    marginBottom: spacing.md,
  },
  keyIconContainer: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.md,
  },
  keyName: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.text,
    marginBottom: spacing.sm,
    textAlign: 'center',
  },
  keyBadges: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: spacing.sm,
  },
  typeBadge: {
    backgroundColor: colors.surfaceHighlight,
    paddingHorizontal: spacing.sm,
    paddingVertical: 4,
    borderRadius: borderRadius.sm,
  },
  typeBadgeText: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textMuted,
    letterSpacing: 0.5,
  },
  importedBadge: {
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    paddingHorizontal: spacing.sm,
    paddingVertical: 4,
    borderRadius: borderRadius.sm,
  },
  importedBadgeText: {
    fontSize: fontSize.xs,
    fontWeight: '600',
    color: colors.primary,
  },
  biometricBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    paddingHorizontal: spacing.sm,
    paddingVertical: 4,
    borderRadius: borderRadius.sm,
    gap: 4,
  },
  biometricBadgeText: {
    fontSize: fontSize.xs,
    fontWeight: '600',
    color: colors.primary,
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
    marginBottom: spacing.sm,
    paddingHorizontal: spacing.xs,
  },
  // Details Card
  detailsCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  detailRow: {
    paddingVertical: spacing.sm,
  },
  detailLabel: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    marginBottom: 4,
  },
  detailValue: {
    fontSize: fontSize.md,
    color: colors.text,
    fontWeight: '500',
  },
  monoText: {
    fontFamily: 'monospace',
    fontSize: fontSize.sm,
  },
  monoInline: {
    fontFamily: 'monospace',
    color: colors.primary,
  },
  separator: {
    height: 1,
    backgroundColor: colors.borderLight,
    marginVertical: spacing.xs,
  },
  // Public Key
  publicKeyCard: {
    backgroundColor: '#0b0f13',
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.1)',
    marginBottom: spacing.md,
  },
  publicKeyText: {
    fontFamily: 'monospace',
    fontSize: fontSize.sm,
    color: colors.text,
    lineHeight: 20,
  },
  copyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.xl,
    gap: spacing.sm,
  },
  copyButtonPressed: {
    backgroundColor: colors.primaryDark,
    transform: [{ scale: 0.98 }],
  },
  copyButtonCopied: {
    backgroundColor: colors.success,
  },
  copyButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.background,
    letterSpacing: -0.3,
  },
  copyButtonTextCopied: {
    color: colors.background,
  },
  // Usage Card
  usageCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  usageTitle: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
    marginBottom: spacing.xs,
  },
  usageDescription: {
    fontSize: fontSize.sm,
    color: colors.textSecondary,
    lineHeight: 20,
  },
  // Danger Zone
  dangerCard: {
    backgroundColor: 'rgba(239, 68, 68, 0.05)',
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: 'rgba(239, 68, 68, 0.2)',
  },
  dangerInfo: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    marginBottom: spacing.md,
  },
  dangerTextContainer: {
    flex: 1,
  },
  dangerTitle: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.error,
    marginBottom: 4,
  },
  dangerDescription: {
    fontSize: fontSize.sm,
    color: colors.textSecondary,
    lineHeight: 18,
  },
  deleteButton: {
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.error,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.lg,
  },
  deleteButtonPressed: {
    opacity: 0.8,
    transform: [{ scale: 0.98 }],
  },
  deleteButtonDisabled: {
    opacity: 0.5,
  },
  deleteButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.text,
  },
});
