/**
 * KeyCard
 *
 * SSH鍵の情報を表示するカードコンポーネント。
 * 名前、タイプ、フィンガープリント、作成日を表示。
 */
import { memo } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';

import type { SSHKey } from '@/types/sshKey';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

export interface KeyCardProps {
  /** SSH鍵データ */
  sshKey: SSHKey;
  /** カード押下時のコールバック */
  onPress?: () => void;
}

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

/**
 * 鍵タイプのアイコンを取得
 */
function getKeyIcon(keyType: string): string {
  switch (keyType) {
    case 'ed25519':
      return 'key-variant';
    case 'rsa-2048':
    case 'rsa-4096':
      return 'key';
    case 'ecdsa':
      return 'key-chain';
    default:
      return 'key-outline';
  }
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
      return 'ECDSA';
    default:
      return keyType.toUpperCase();
  }
}

export const KeyCard = memo(function KeyCard({ sshKey, onPress }: KeyCardProps) {
  return (
    <Pressable
      style={({ pressed }) => [
        styles.container,
        pressed && styles.containerPressed,
      ]}
      onPress={onPress}
    >
      {/* Icon */}
      <View style={styles.iconContainer}>
        <MaterialCommunityIcons
          name={getKeyIcon(sshKey.keyType) as keyof typeof MaterialCommunityIcons.glyphMap}
          size={24}
          color={colors.primary}
        />
      </View>

      {/* Info */}
      <View style={styles.info}>
        <View style={styles.nameRow}>
          <Text style={styles.name} numberOfLines={1}>
            {sshKey.name}
          </Text>
          {sshKey.imported && (
            <View style={styles.importedBadge}>
              <Text style={styles.importedText}>Imported</Text>
            </View>
          )}
        </View>

        <View style={styles.metaRow}>
          <View style={styles.typeBadge}>
            <Text style={styles.typeText}>{getKeyTypeLabel(sshKey.keyType)}</Text>
          </View>
          <Text style={styles.date}>{formatDate(sshKey.createdAt)}</Text>
          {sshKey.requireBiometrics && (
            <MaterialCommunityIcons
              name="fingerprint"
              size={14}
              color={colors.textMuted}
            />
          )}
        </View>

        <Text style={styles.fingerprint} numberOfLines={1}>
          {sshKey.fingerprint}
        </Text>
      </View>

      {/* Chevron */}
      <MaterialCommunityIcons
        name="chevron-right"
        size={20}
        color={colors.textMuted}
      />
    </Pressable>
  );
});

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderLight,
    gap: spacing.md,
  },
  containerPressed: {
    backgroundColor: colors.surfaceHighlight,
  },
  iconContainer: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  info: {
    flex: 1,
    gap: 4,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  name: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
    flex: 1,
  },
  importedBadge: {
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
  },
  importedText: {
    fontSize: fontSize.xxs,
    fontWeight: '600',
    color: colors.primary,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  typeBadge: {
    backgroundColor: colors.surfaceHighlight,
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
  },
  typeText: {
    fontSize: fontSize.xxs,
    fontWeight: '700',
    color: colors.textMuted,
    letterSpacing: 0.5,
  },
  date: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
  fingerprint: {
    fontSize: fontSize.xs,
    color: colors.textDim,
    fontFamily: 'monospace',
  },
});
