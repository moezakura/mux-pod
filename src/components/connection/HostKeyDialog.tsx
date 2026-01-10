/**
 * HostKeyDialog
 *
 * ホスト鍵確認・警告ダイアログコンポーネント。
 * 新しいホストの確認と、鍵変更時の警告を表示。
 */
import { memo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Modal,
  Pressable,
  ScrollView,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';

import type { HostKeyType } from '@/types/sshKey';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

export type HostKeyDialogType = 'unknown' | 'changed';

export interface HostKeyDialogProps {
  /** ダイアログを表示するか */
  visible: boolean;
  /** ダイアログタイプ */
  type: HostKeyDialogType;
  /** ホスト名 */
  host: string;
  /** ポート番号 */
  port: number;
  /** 鍵タイプ */
  keyType: HostKeyType;
  /** フィンガープリント */
  fingerprint: string;
  /** 以前のフィンガープリント（changedタイプの場合） */
  previousFingerprint?: string;
  /** 信頼ボタン押下時のコールバック */
  onTrust: () => void;
  /** キャンセルボタン押下時のコールバック */
  onCancel: () => void;
  /** 読み込み中か */
  loading?: boolean;
}

export const HostKeyDialog = memo(function HostKeyDialog({
  visible,
  type,
  host,
  port,
  keyType,
  fingerprint,
  previousFingerprint,
  onTrust,
  onCancel,
  loading = false,
}: HostKeyDialogProps) {
  const isChanged = type === 'changed';

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onCancel}
    >
      <View style={styles.overlay}>
        <View style={[styles.dialog, isChanged && styles.dialogDanger]}>
          <ScrollView
            showsVerticalScrollIndicator={false}
            contentContainerStyle={styles.scrollContent}
          >
            {/* Icon */}
            <View
              style={[
                styles.iconContainer,
                isChanged && styles.iconContainerDanger,
              ]}
            >
              <MaterialCommunityIcons
                name={isChanged ? 'alert' : 'shield-key-outline'}
                size={48}
                color={isChanged ? colors.error : colors.warning}
              />
            </View>

            {/* Title */}
            <Text style={[styles.title, isChanged && styles.titleDanger]}>
              {isChanged ? 'Host Key Changed!' : 'New Host Key'}
            </Text>

            {/* Description */}
            <Text style={styles.description}>
              {isChanged
                ? 'The host key for this server has changed. This could indicate a man-in-the-middle attack, or the server has been reinstalled.'
                : `You are connecting to ${host} for the first time. Please verify the host key fingerprint before continuing.`}
            </Text>

            {/* Host Info */}
            <View style={styles.hostInfo}>
              <View style={styles.hostInfoRow}>
                <Text style={styles.hostInfoLabel}>Host</Text>
                <Text style={styles.hostInfoValue} selectable>
                  {host}:{port}
                </Text>
              </View>
              <View style={styles.separator} />
              <View style={styles.hostInfoRow}>
                <Text style={styles.hostInfoLabel}>Key Type</Text>
                <Text style={styles.hostInfoValue}>{keyType}</Text>
              </View>
            </View>

            {/* Fingerprints */}
            <View style={styles.fingerprintSection}>
              {isChanged && previousFingerprint && (
                <>
                  <Text style={styles.fingerprintLabel}>Previous Fingerprint</Text>
                  <View style={[styles.fingerprintBox, styles.fingerprintBoxOld]}>
                    <Text style={styles.fingerprintText} selectable>
                      {previousFingerprint}
                    </Text>
                  </View>
                </>
              )}

              <Text style={styles.fingerprintLabel}>
                {isChanged ? 'New Fingerprint' : 'Fingerprint'}
              </Text>
              <View
                style={[
                  styles.fingerprintBox,
                  isChanged && styles.fingerprintBoxNew,
                ]}
              >
                <Text style={styles.fingerprintText} selectable>
                  {fingerprint}
                </Text>
              </View>
            </View>

            {/* Warning for changed keys */}
            {isChanged && (
              <View style={styles.warningBox}>
                <MaterialCommunityIcons
                  name="alert-circle"
                  size={20}
                  color={colors.error}
                />
                <Text style={styles.warningText}>
                  Only continue if you are certain this change is expected. If in
                  doubt, contact your server administrator.
                </Text>
              </View>
            )}
          </ScrollView>

          {/* Actions */}
          <View style={styles.actions}>
            <Pressable
              style={[styles.cancelButton]}
              onPress={onCancel}
              disabled={loading}
            >
              <Text style={styles.cancelButtonText}>Cancel</Text>
            </Pressable>

            <Pressable
              style={[
                styles.trustButton,
                isChanged && styles.trustButtonDanger,
                loading && styles.buttonDisabled,
              ]}
              onPress={onTrust}
              disabled={loading}
            >
              <Text style={styles.trustButtonText}>
                {loading
                  ? 'Saving...'
                  : isChanged
                  ? 'Trust Anyway'
                  : 'Trust Host'}
              </Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
});

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.md,
  },
  dialog: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    width: '100%',
    maxWidth: 400,
    maxHeight: '80%',
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  dialogDanger: {
    borderColor: colors.error,
    borderWidth: 2,
  },
  scrollContent: {
    padding: spacing.lg,
  },
  iconContainer: {
    alignSelf: 'center',
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(245, 158, 11, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.md,
  },
  iconContainerDanger: {
    backgroundColor: 'rgba(239, 68, 68, 0.1)',
  },
  title: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.warning,
    textAlign: 'center',
    marginBottom: spacing.sm,
  },
  titleDanger: {
    color: colors.error,
  },
  description: {
    fontSize: fontSize.md,
    color: colors.textSecondary,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: spacing.lg,
  },
  hostInfo: {
    backgroundColor: colors.background,
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  hostInfoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.xs,
  },
  hostInfoLabel: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  hostInfoValue: {
    fontSize: fontSize.md,
    color: colors.text,
    fontWeight: '500',
    fontFamily: 'monospace',
  },
  separator: {
    height: 1,
    backgroundColor: colors.borderLight,
    marginVertical: spacing.xs,
  },
  fingerprintSection: {
    marginBottom: spacing.md,
  },
  fingerprintLabel: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    letterSpacing: 1,
    color: colors.textMuted,
    textTransform: 'uppercase',
    marginBottom: spacing.xs,
  },
  fingerprintBox: {
    backgroundColor: colors.background,
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderLight,
    marginBottom: spacing.sm,
  },
  fingerprintBoxOld: {
    borderColor: 'rgba(239, 68, 68, 0.3)',
    opacity: 0.7,
  },
  fingerprintBoxNew: {
    borderColor: colors.error,
  },
  fingerprintText: {
    fontSize: fontSize.sm,
    color: colors.text,
    fontFamily: 'monospace',
    lineHeight: 18,
  },
  warningBox: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    backgroundColor: 'rgba(239, 68, 68, 0.1)',
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  warningText: {
    flex: 1,
    fontSize: fontSize.sm,
    color: colors.error,
    lineHeight: 18,
  },
  actions: {
    flexDirection: 'row',
    padding: spacing.md,
    gap: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
  },
  cancelButton: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  cancelButtonText: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  trustButton: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    backgroundColor: colors.warning,
  },
  trustButtonDanger: {
    backgroundColor: colors.error,
  },
  trustButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.background,
  },
  buttonDisabled: {
    opacity: 0.5,
  },
});
