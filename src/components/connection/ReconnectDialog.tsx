/**
 * ReconnectDialog
 *
 * SSH接続が切断された際に表示される再接続確認ダイアログ。
 */
import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  Modal,
  Pressable,
  TextInput,
  ActivityIndicator,
  StyleSheet,
} from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import type { Connection, ConnectionState, DisconnectReason } from '@/types/connection';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

/**
 * Props
 */
export interface ReconnectDialogProps {
  /** 表示するかどうか */
  visible: boolean;
  /** 再接続対象の接続 */
  connection: Connection;
  /** 接続状態 */
  connectionState: ConnectionState;
  /** 再接続ボタン押下時 */
  onReconnect: (password?: string) => void;
  /** キャンセルボタン押下時 */
  onCancel: () => void;
  /** ダイアログを閉じる */
  onDismiss: () => void;
  /** 再試行ボタン押下時 */
  onRetry?: () => void;
}

/**
 * 切断理由を日本語に変換
 */
function getDisconnectReasonText(reason?: DisconnectReason): string {
  switch (reason) {
    case 'network_error':
      return 'ネットワークエラーにより切断されました';
    case 'server_closed':
      return 'サーバーにより切断されました';
    case 'auth_failed':
      return '認証に失敗しました';
    case 'timeout':
      return '接続がタイムアウトしました';
    case 'user_disconnect':
      return '切断されました';
    default:
      return '接続が切断されました';
  }
}

/**
 * ReconnectDialog
 */
export function ReconnectDialog({
  visible,
  connection,
  connectionState,
  onReconnect,
  onCancel,
  onDismiss,
  onRetry,
}: ReconnectDialogProps): React.JSX.Element | null {
  const [password, setPassword] = useState('');
  const [showPasswordInput, setShowPasswordInput] = useState(false);

  const { status, error, disconnectReason, reconnectAttempt } = connectionState;

  // ダイアログが閉じたらパスワード入力をリセット
  useEffect(() => {
    if (!visible) {
      setPassword('');
      setShowPasswordInput(false);
    }
  }, [visible]);

  if (!visible) {
    return null;
  }

  // 接続成功時
  if (status === 'connected') {
    return (
      <Modal
        visible={visible}
        transparent
        animationType="fade"
        onRequestClose={onDismiss}
      >
        <View style={styles.overlay} testID="reconnect-dialog">
          <View style={styles.dialog}>
            <View style={styles.successIcon}>
              <MaterialIcons name="check-circle" size={48} color={colors.success} />
            </View>
            <Text style={styles.title}>接続しました</Text>
            <Text style={styles.message}>{connection.name} に接続しました</Text>
          </View>
        </View>
      </Modal>
    );
  }

  // エラー時
  if (status === 'error') {
    return (
      <Modal
        visible={visible}
        transparent
        animationType="fade"
        onRequestClose={onDismiss}
      >
        <View style={styles.overlay} testID="reconnect-dialog">
          <View style={styles.dialog}>
            <View style={styles.errorIcon}>
              <MaterialIcons name="error" size={48} color={colors.error} />
            </View>
            <Text style={styles.title}>接続エラー</Text>
            <Text style={styles.errorMessage}>{error}</Text>
            <View style={styles.buttonRow}>
              {onRetry && (
                <Pressable
                  style={[styles.button, styles.primaryButton]}
                  onPress={onRetry}
                >
                  <Text style={styles.primaryButtonText}>再試行</Text>
                </Pressable>
              )}
              <Pressable
                style={[styles.button, styles.secondaryButton]}
                onPress={onCancel}
              >
                <Text style={styles.secondaryButtonText}>閉じる</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    );
  }

  // 再接続中
  if (status === 'reconnecting') {
    return (
      <Modal
        visible={visible}
        transparent
        animationType="fade"
        onRequestClose={onDismiss}
      >
        <View style={styles.overlay} testID="reconnect-dialog">
          <View style={styles.dialog}>
            <ActivityIndicator
              testID="connecting-spinner"
              size="large"
              color={colors.primary}
            />
            <Text style={styles.title}>再接続中...</Text>
            {reconnectAttempt && (
              <Text style={styles.attemptText}>
                試行 {reconnectAttempt.attemptNumber} / {reconnectAttempt.maxAttempts}
              </Text>
            )}
            <Pressable
              style={[styles.button, styles.secondaryButton, styles.cancelButton]}
              onPress={onCancel}
            >
              <Text style={styles.secondaryButtonText}>キャンセル</Text>
            </Pressable>
          </View>
        </View>
      </Modal>
    );
  }

  // パスワード入力
  if (showPasswordInput) {
    return (
      <Modal
        visible={visible}
        transparent
        animationType="fade"
        onRequestClose={onDismiss}
      >
        <View style={styles.overlay} testID="reconnect-dialog">
          <View style={styles.dialog}>
            <Text style={styles.title}>パスワードを入力</Text>
            <Text style={styles.message}>{connection.name}</Text>
            <TextInput
              style={styles.input}
              placeholder="パスワード"
              placeholderTextColor="rgba(255, 255, 255, 0.4)"
              secureTextEntry
              value={password}
              onChangeText={setPassword}
              autoFocus
            />
            <View style={styles.buttonRow}>
              <Pressable
                style={[styles.button, styles.primaryButton]}
                onPress={() => onReconnect(password)}
              >
                <Text style={styles.primaryButtonText}>接続</Text>
              </Pressable>
              <Pressable
                style={[styles.button, styles.secondaryButton]}
                onPress={onCancel}
              >
                <Text style={styles.secondaryButtonText}>キャンセル</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    );
  }

  // 確認ダイアログ（初期状態）
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onDismiss}
    >
      <View style={styles.overlay} testID="reconnect-dialog">
        <View style={styles.dialog}>
          <View style={styles.warningIcon}>
            <MaterialIcons name="wifi-off" size={48} color={colors.warning} />
          </View>
          <Text style={styles.title}>接続が切断されました</Text>
          <Text style={styles.connectionName}>{connection.name}</Text>
          <Text style={styles.message}>
            {getDisconnectReasonText(disconnectReason)}
          </Text>
          <View style={styles.buttonRow}>
            <Pressable
              style={[styles.button, styles.primaryButton]}
              onPress={() => onReconnect()}
            >
              <Text style={styles.primaryButtonText}>再接続</Text>
            </Pressable>
            <Pressable
              style={[styles.button, styles.secondaryButton]}
              onPress={onCancel}
            >
              <Text style={styles.secondaryButtonText}>キャンセル</Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
  },
  dialog: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.xl,
    width: '100%',
    maxWidth: 320,
    alignItems: 'center',
  },
  warningIcon: {
    marginBottom: spacing.md,
  },
  successIcon: {
    marginBottom: spacing.md,
  },
  errorIcon: {
    marginBottom: spacing.md,
  },
  title: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
    marginBottom: spacing.sm,
    textAlign: 'center',
  },
  connectionName: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.primary,
    marginBottom: spacing.xs,
  },
  message: {
    fontSize: fontSize.sm,
    color: colors.textSecondary,
    textAlign: 'center',
    marginBottom: spacing.lg,
  },
  errorMessage: {
    fontSize: fontSize.sm,
    color: colors.error,
    textAlign: 'center',
    marginBottom: spacing.lg,
  },
  attemptText: {
    fontSize: fontSize.sm,
    color: colors.textSecondary,
    marginTop: spacing.md,
    marginBottom: spacing.lg,
  },
  buttonRow: {
    flexDirection: 'row',
    gap: spacing.sm,
    width: '100%',
  },
  button: {
    flex: 1,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.md,
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: colors.primary,
  },
  primaryButtonText: {
    color: colors.background,
    fontWeight: '600',
    fontSize: fontSize.sm,
  },
  secondaryButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
  },
  secondaryButtonText: {
    color: colors.textSecondary,
    fontWeight: '600',
    fontSize: fontSize.sm,
  },
  cancelButton: {
    marginTop: spacing.lg,
    flex: 0,
    paddingHorizontal: spacing.xl,
  },
  input: {
    width: '100%',
    backgroundColor: 'rgba(0, 0, 0, 0.3)',
    borderRadius: borderRadius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    fontSize: fontSize.md,
    color: colors.text,
    marginBottom: spacing.lg,
  },
});
