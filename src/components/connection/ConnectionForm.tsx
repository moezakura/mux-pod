/**
 * ConnectionForm
 *
 * 接続設定の入力フォームコンポーネント。
 * HTMLデザイン (add_connection_screen.html) に完全準拠。
 */
import { useState, useCallback } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  Pressable,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import type { ConnectionInput } from '@/types/connection';
import { DEFAULT_RECONNECT_SETTINGS } from '@/types/connection';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

export interface ConnectionFormProps {
  /** 初期値（編集時） */
  initialValues?: Partial<ConnectionInput>;
  /** 送信時のコールバック */
  onSubmit: (values: ConnectionInput) => void;
  /** キャンセル時のコールバック */
  onCancel?: () => void;
  /** 送信ボタンのラベル */
  submitLabel?: string;
  /** 読み込み中かどうか */
  loading?: boolean;
  /** テスト接続コールバック */
  onTestConnection?: (values: ConnectionInput) => Promise<boolean>;
}

interface FormErrors {
  name?: string;
  host?: string;
  port?: string;
  username?: string;
}

/**
 * フォーム値をバリデートする
 */
function validateForm(values: Partial<ConnectionInput>): FormErrors {
  const errors: FormErrors = {};

  if (!values.name || values.name.trim() === '') {
    errors.name = 'Connection name is required';
  } else if (values.name.length > 50) {
    errors.name = 'Connection name must be 50 characters or less';
  }

  if (!values.host || values.host.trim() === '') {
    errors.host = 'Host is required';
  }

  if (!values.port || values.port < 1 || values.port > 65535) {
    errors.port = 'Port must be between 1-65535';
  }

  if (!values.username || values.username.trim() === '') {
    errors.username = 'Username is required';
  } else if (values.username.length > 32) {
    errors.username = 'Username must be 32 characters or less';
  }

  return errors;
}

/**
 * ホストのバリデーション
 */
function isValidHost(host: string): boolean {
  if (!host) return false;
  // Simple validation: IP address or hostname
  const ipRegex = /^(\d{1,3}\.){3}\d{1,3}$/;
  const hostnameRegex = /^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$/;
  return ipRegex.test(host) || hostnameRegex.test(host) || host.length > 0;
}

/**
 * セクションヘッダー
 */
function SectionHeader({ title, icon }: { title: string; icon?: string }) {
  return (
    <View style={styles.sectionHeader}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {icon && (
        <MaterialCommunityIcons
          name={icon as keyof typeof MaterialCommunityIcons.glyphMap}
          size={16}
          color={colors.textMuted}
        />
      )}
    </View>
  );
}

export function ConnectionForm({
  initialValues,
  onSubmit,
  onCancel,
  submitLabel = 'Save',
  loading = false,
  onTestConnection,
}: ConnectionFormProps) {
  const [name, setName] = useState(initialValues?.name ?? '');
  const [host, setHost] = useState(initialValues?.host ?? '');
  const [port, setPort] = useState(String(initialValues?.port ?? 22));
  const [timeout, setTimeout] = useState(String(initialValues?.timeout ?? 10));
  const [username, setUsername] = useState(initialValues?.username ?? '');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [authMethod, setAuthMethod] = useState<'password' | 'key'>(
    initialValues?.authMethod ?? 'password'
  );
  const [protocol, setProtocol] = useState<'ssh' | 'mosh'>('ssh');
  const [errors, setErrors] = useState<FormErrors>({});
  const [testing, setTesting] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  // 自動再接続設定
  const [autoReconnect, setAutoReconnect] = useState(
    initialValues?.autoReconnect ?? DEFAULT_RECONNECT_SETTINGS.autoReconnect
  );
  const [maxReconnectAttempts, setMaxReconnectAttempts] = useState(
    String(initialValues?.maxReconnectAttempts ?? DEFAULT_RECONNECT_SETTINGS.maxReconnectAttempts)
  );
  const [reconnectInterval, setReconnectInterval] = useState(
    String((initialValues?.reconnectInterval ?? DEFAULT_RECONNECT_SETTINGS.reconnectInterval) / 1000)
  );

  const handleSubmit = useCallback(() => {
    const values: Partial<ConnectionInput> = {
      name: name.trim(),
      host: host.trim(),
      port: parseInt(port, 10) || 22,
      username: username.trim(),
      authMethod,
      timeout: parseInt(timeout, 10) || 10,
      keepAliveInterval: initialValues?.keepAliveInterval ?? 60,
      autoReconnect,
      maxReconnectAttempts: parseInt(maxReconnectAttempts, 10) || DEFAULT_RECONNECT_SETTINGS.maxReconnectAttempts,
      reconnectInterval: (parseInt(reconnectInterval, 10) || DEFAULT_RECONNECT_SETTINGS.reconnectInterval / 1000) * 1000,
    };

    const validationErrors = validateForm(values);
    if (Object.keys(validationErrors).length > 0) {
      setErrors(validationErrors);
      return;
    }

    setErrors({});
    onSubmit(values as ConnectionInput);
  }, [name, host, port, timeout, username, authMethod, initialValues, onSubmit, autoReconnect, maxReconnectAttempts, reconnectInterval]);

  const handleTestConnection = useCallback(async () => {
    const values: Partial<ConnectionInput> = {
      name: name.trim(),
      host: host.trim(),
      port: parseInt(port, 10) || 22,
      username: username.trim(),
      authMethod,
      timeout: parseInt(timeout, 10) || 10,
      keepAliveInterval: 60,
    };

    const validationErrors = validateForm(values);
    if (Object.keys(validationErrors).length > 0) {
      setErrors(validationErrors);
      return;
    }

    setErrors({});
    setTesting(true);
    try {
      if (onTestConnection) {
        await onTestConnection(values as ConnectionInput);
      }
    } finally {
      setTesting(false);
    }
  }, [name, host, port, timeout, username, authMethod, onTestConnection]);

  const hostValid = isValidHost(host);

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      {/* Header */}
      <View style={styles.header}>
        <Pressable onPress={onCancel} style={styles.headerButton}>
          <Text style={styles.headerButtonText}>Cancel</Text>
        </Pressable>
        <Text style={styles.headerTitle}>Add Connection</Text>
        <Pressable
          onPress={handleSubmit}
          disabled={loading}
          style={styles.headerButton}
        >
          <Text style={[styles.headerButtonText, styles.headerSaveText]}>
            {loading ? 'Saving...' : submitLabel}
          </Text>
        </Pressable>
      </View>

      <KeyboardAvoidingView
        style={styles.keyboardView}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
        >
          {/* Section: General Info */}
          <View style={styles.section}>
            <SectionHeader title="GENERAL INFO" icon="information-outline" />
            <View style={styles.sectionCard}>
              <View style={styles.inputContainer}>
                <View style={styles.inputIconContainer}>
                  <MaterialCommunityIcons
                    name="label-outline"
                    size={20}
                    color={colors.textMuted}
                  />
                </View>
                <TextInput
                  style={styles.inputWithIcon}
                  value={name}
                  onChangeText={setName}
                  placeholder="e.g. Production AWS"
                  placeholderTextColor={colors.textMuted}
                  autoCapitalize="none"
                />
                <Text style={styles.floatingLabel}>CONNECTION NAME</Text>
              </View>
              {errors.name && <Text style={styles.errorText}>{errors.name}</Text>}
            </View>
          </View>

          {/* Section: Network */}
          <View style={styles.section}>
            <SectionHeader title="NETWORK" />
            <View style={styles.sectionCard}>
              {/* Host Field */}
              <View style={styles.fieldGroup}>
                <Text style={styles.fieldLabel}>HOST / IP ADDRESS</Text>
                <View style={styles.inputRow}>
                  <TextInput
                    style={[styles.input, styles.inputMono]}
                    value={host}
                    onChangeText={setHost}
                    placeholder="192.168.1.1 or example.com"
                    placeholderTextColor={colors.textDim}
                    autoCapitalize="none"
                    autoCorrect={false}
                    keyboardType="url"
                  />
                  {host.length > 0 && (
                    <View style={styles.validationDot}>
                      <View
                        style={[
                          styles.dot,
                          hostValid ? styles.dotValid : styles.dotInvalid,
                        ]}
                      />
                    </View>
                  )}
                </View>
                {errors.host && <Text style={styles.errorText}>{errors.host}</Text>}
              </View>

              {/* Port & Timeout Row */}
              <View style={styles.rowFields}>
                <View style={styles.fieldHalf}>
                  <Text style={styles.fieldLabel}>PORT</Text>
                  <TextInput
                    style={[styles.input, styles.inputMono]}
                    value={port}
                    onChangeText={setPort}
                    placeholder="22"
                    placeholderTextColor={colors.textDim}
                    keyboardType="number-pad"
                  />
                  {errors.port && <Text style={styles.errorText}>{errors.port}</Text>}
                </View>
                <View style={styles.fieldThird}>
                  <Text style={styles.fieldLabel}>TIMEOUT</Text>
                  <View style={styles.timeoutContainer}>
                    <TextInput
                      style={[styles.input, styles.inputMono, styles.inputCenter]}
                      value={timeout}
                      onChangeText={setTimeout}
                      placeholder="10"
                      placeholderTextColor={colors.textDim}
                      keyboardType="number-pad"
                    />
                    <Text style={styles.timeoutUnit}>s</Text>
                  </View>
                </View>
              </View>
            </View>
          </View>

          {/* Section: Security & Auth */}
          <View style={styles.section}>
            <View style={styles.sectionHeaderWithBadges}>
              <Text style={styles.sectionTitle}>SECURITY & AUTH</Text>
              <View style={styles.protocolBadges}>
                <Pressable
                  style={[
                    styles.protocolBadge,
                    protocol === 'ssh' && styles.protocolBadgeActive,
                  ]}
                  onPress={() => setProtocol('ssh')}
                >
                  <Text
                    style={[
                      styles.protocolBadgeText,
                      protocol === 'ssh' && styles.protocolBadgeTextActive,
                    ]}
                  >
                    SSH
                  </Text>
                </Pressable>
                <Pressable
                  style={[
                    styles.protocolBadge,
                    protocol === 'mosh' && styles.protocolBadgeActive,
                  ]}
                  onPress={() => setProtocol('mosh')}
                >
                  <Text
                    style={[
                      styles.protocolBadgeText,
                      protocol === 'mosh' && styles.protocolBadgeTextActive,
                    ]}
                  >
                    MOSH
                  </Text>
                </Pressable>
              </View>
            </View>

            <View style={styles.sectionCard}>
              {/* Username */}
              <View style={styles.inputContainer}>
                <View style={styles.inputIconContainerLeft}>
                  <MaterialCommunityIcons
                    name="account-outline"
                    size={20}
                    color={colors.textMuted}
                  />
                </View>
                <TextInput
                  style={[styles.inputWithLeftIcon, styles.inputMono]}
                  value={username}
                  onChangeText={setUsername}
                  placeholder="root"
                  placeholderTextColor={colors.textDim}
                  autoCapitalize="none"
                  autoCorrect={false}
                />
                <Text style={styles.inputSuffix}>USER</Text>
              </View>
              {errors.username && (
                <Text style={styles.errorText}>{errors.username}</Text>
              )}

              {/* Separator */}
              <View style={styles.separator} />

              {/* Auth Method Toggle */}
              <View style={styles.authToggleContainer}>
                <Pressable
                  style={[
                    styles.authToggleButton,
                    authMethod === 'password' && styles.authToggleButtonActive,
                  ]}
                  onPress={() => setAuthMethod('password')}
                >
                  <Text
                    style={[
                      styles.authToggleText,
                      authMethod === 'password' && styles.authToggleTextActive,
                    ]}
                  >
                    Password
                  </Text>
                </Pressable>
                <Pressable
                  style={[
                    styles.authToggleButton,
                    authMethod === 'key' && styles.authToggleButtonActive,
                  ]}
                  onPress={() => setAuthMethod('key')}
                >
                  <Text
                    style={[
                      styles.authToggleText,
                      authMethod === 'key' && styles.authToggleTextActive,
                    ]}
                  >
                    Private Key
                  </Text>
                </Pressable>
              </View>

              {/* Password/Key Input */}
              {authMethod === 'password' ? (
                <View style={styles.inputContainer}>
                  <View style={styles.inputIconContainerLeft}>
                    <MaterialCommunityIcons
                      name="key-outline"
                      size={20}
                      color={colors.textMuted}
                    />
                  </View>
                  <TextInput
                    style={[styles.inputWithLeftIcon, styles.inputMono]}
                    value={password}
                    onChangeText={setPassword}
                    placeholder="Enter password"
                    placeholderTextColor={colors.textDim}
                    secureTextEntry={!showPassword}
                    autoCapitalize="none"
                    autoCorrect={false}
                  />
                  <Pressable
                    style={styles.visibilityButton}
                    onPress={() => setShowPassword(!showPassword)}
                  >
                    <MaterialCommunityIcons
                      name={showPassword ? 'eye-outline' : 'eye-off-outline'}
                      size={20}
                      color={colors.textMuted}
                    />
                  </Pressable>
                </View>
              ) : (
                <Pressable style={styles.keySelectButton}>
                  <MaterialCommunityIcons
                    name="key-outline"
                    size={20}
                    color={colors.primary}
                  />
                  <Text style={styles.keySelectText}>Select Private Key</Text>
                  <MaterialCommunityIcons
                    name="chevron-right"
                    size={20}
                    color={colors.textMuted}
                  />
                </Pressable>
              )}
            </View>
          </View>

          {/* Advanced Options Toggle */}
          <Pressable
            style={styles.advancedToggle}
            onPress={() => setShowAdvanced(!showAdvanced)}
          >
            <Text style={styles.advancedToggleText}>
              {showAdvanced ? 'Hide' : 'Show'} Advanced Options
            </Text>
            <MaterialCommunityIcons
              name={showAdvanced ? 'chevron-up' : 'chevron-down'}
              size={16}
              color={colors.textMuted}
            />
          </Pressable>

          {/* Advanced Options Section */}
          {showAdvanced && (
            <View style={styles.section}>
              <SectionHeader title="AUTO RECONNECT" icon="refresh" />
              <View style={styles.sectionCard}>
                {/* Auto Reconnect Toggle */}
                <View style={styles.toggleRow}>
                  <View style={styles.toggleLabelContainer}>
                    <MaterialCommunityIcons
                      name="refresh-auto"
                      size={20}
                      color={colors.textMuted}
                    />
                    <View>
                      <Text style={styles.toggleLabel}>Auto Reconnect</Text>
                      <Text style={styles.toggleDescription}>
                        Automatically reconnect on disconnect
                      </Text>
                    </View>
                  </View>
                  <Pressable
                    style={[
                      styles.toggleSwitch,
                      autoReconnect && styles.toggleSwitchActive,
                    ]}
                    onPress={() => setAutoReconnect(!autoReconnect)}
                  >
                    <View
                      style={[
                        styles.toggleKnob,
                        autoReconnect && styles.toggleKnobActive,
                      ]}
                    />
                  </Pressable>
                </View>

                {/* Reconnect Settings (shown when auto-reconnect is enabled) */}
                {autoReconnect && (
                  <>
                    <View style={styles.separator} />
                    <View style={styles.rowFields}>
                      <View style={styles.fieldHalf}>
                        <Text style={styles.fieldLabel}>MAX ATTEMPTS</Text>
                        <TextInput
                          style={[styles.input, styles.inputMono, styles.inputCenter]}
                          value={maxReconnectAttempts}
                          onChangeText={setMaxReconnectAttempts}
                          placeholder="3"
                          placeholderTextColor={colors.textDim}
                          keyboardType="number-pad"
                        />
                      </View>
                      <View style={styles.fieldHalf}>
                        <Text style={styles.fieldLabel}>INTERVAL</Text>
                        <View style={styles.timeoutContainer}>
                          <TextInput
                            style={[styles.input, styles.inputMono, styles.inputCenter]}
                            value={reconnectInterval}
                            onChangeText={setReconnectInterval}
                            placeholder="5"
                            placeholderTextColor={colors.textDim}
                            keyboardType="number-pad"
                          />
                          <Text style={styles.timeoutUnit}>s</Text>
                        </View>
                      </View>
                    </View>
                  </>
                )}
              </View>
            </View>
          )}

          {/* Spacer for bottom button */}
          <View style={styles.bottomSpacer} />
        </ScrollView>
      </KeyboardAvoidingView>

      {/* Fixed Bottom Button */}
      <View style={styles.bottomButtonContainer}>
        <Pressable
          style={({ pressed }) => [
            styles.testButton,
            pressed && styles.testButtonPressed,
            testing && styles.testButtonDisabled,
          ]}
          onPress={handleTestConnection}
          disabled={testing}
        >
          <MaterialCommunityIcons
            name="console"
            size={20}
            color={colors.background}
          />
          <Text style={styles.testButtonText}>
            {testing ? 'TESTING...' : 'TEST CONNECTION'}
          </Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0f141a',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255, 255, 255, 0.05)',
    backgroundColor: 'rgba(15, 20, 26, 0.9)',
  },
  headerButton: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
  },
  headerButtonText: {
    fontSize: fontSize.md,
    fontWeight: '500',
    color: colors.textSecondary,
  },
  headerSaveText: {
    color: colors.primary,
    fontWeight: '700',
  },
  headerTitle: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
    letterSpacing: -0.3,
  },
  keyboardView: {
    flex: 1,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: spacing.md,
    paddingBottom: 120,
  },
  section: {
    marginBottom: spacing.lg,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.xs,
    marginBottom: spacing.sm,
  },
  sectionHeaderWithBadges: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.xs,
    marginBottom: spacing.sm,
  },
  sectionTitle: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    letterSpacing: 1.5,
    color: colors.textMuted,
    textTransform: 'uppercase',
  },
  sectionCard: {
    backgroundColor: '#1c242b',
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.05)',
  },
  inputContainer: {
    position: 'relative',
  },
  inputIconContainer: {
    position: 'absolute',
    left: spacing.md,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
    zIndex: 1,
  },
  inputIconContainerLeft: {
    position: 'absolute',
    left: spacing.sm,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
    zIndex: 1,
  },
  inputWithIcon: {
    backgroundColor: '#0b0f13',
    borderRadius: borderRadius.lg,
    paddingVertical: spacing.md,
    paddingLeft: 48,
    paddingRight: spacing.md,
    fontSize: fontSize.md,
    fontWeight: '500',
    color: colors.text,
  },
  inputWithLeftIcon: {
    backgroundColor: '#0b0f13',
    borderRadius: borderRadius.lg,
    paddingVertical: 14,
    paddingLeft: 40,
    paddingRight: spacing.md,
    fontSize: fontSize.md,
    color: colors.text,
  },
  floatingLabel: {
    position: 'absolute',
    top: -10,
    left: spacing.md,
    backgroundColor: '#1c242b',
    paddingHorizontal: spacing.xs,
    fontSize: fontSize.xxs,
    fontWeight: '700',
    letterSpacing: 0.5,
    color: colors.primary,
    textTransform: 'uppercase',
  },
  fieldGroup: {
    marginBottom: spacing.md,
  },
  fieldLabel: {
    fontSize: fontSize.xs,
    fontWeight: '500',
    color: colors.textMuted,
    marginBottom: 6,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  inputRow: {
    position: 'relative',
  },
  input: {
    backgroundColor: '#0b0f13',
    borderRadius: borderRadius.lg,
    paddingVertical: 14,
    paddingHorizontal: spacing.md,
    fontSize: fontSize.md,
    color: colors.text,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.1)',
  },
  inputMono: {
    fontFamily: 'monospace',
  },
  inputCenter: {
    textAlign: 'center',
    paddingRight: 24,
  },
  validationDot: {
    position: 'absolute',
    right: spacing.sm,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  dotValid: {
    backgroundColor: colors.success,
    shadowColor: colors.success,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 8,
  },
  dotInvalid: {
    backgroundColor: colors.error,
  },
  rowFields: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  fieldHalf: {
    flex: 1,
  },
  fieldThird: {
    width: '33%',
  },
  timeoutContainer: {
    position: 'relative',
  },
  timeoutUnit: {
    position: 'absolute',
    right: spacing.sm,
    top: 0,
    bottom: 0,
    textAlignVertical: 'center',
    lineHeight: 48,
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
  protocolBadges: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  protocolBadge: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: borderRadius.full,
  },
  protocolBadgeActive: {
    backgroundColor: colors.primary,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.3,
    shadowRadius: 10,
  },
  protocolBadgeText: {
    fontSize: fontSize.xxs,
    fontWeight: '700',
    color: colors.textMuted,
  },
  protocolBadgeTextActive: {
    color: colors.background,
  },
  inputSuffix: {
    position: 'absolute',
    right: spacing.sm,
    top: 0,
    bottom: 0,
    textAlignVertical: 'center',
    lineHeight: 48,
    fontSize: fontSize.xxs,
    fontFamily: 'monospace',
    color: colors.textMuted,
    opacity: 0.5,
  },
  separator: {
    height: 1,
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    marginVertical: spacing.md,
    marginHorizontal: spacing.sm,
  },
  authToggleContainer: {
    flexDirection: 'row',
    backgroundColor: 'rgba(0, 0, 0, 0.4)',
    padding: spacing.xs,
    borderRadius: borderRadius.lg,
    marginBottom: spacing.md,
  },
  authToggleButton: {
    flex: 1,
    paddingVertical: 6,
    borderRadius: borderRadius.md,
    alignItems: 'center',
  },
  authToggleButtonActive: {
    backgroundColor: colors.primary,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.3,
    shadowRadius: 5,
  },
  authToggleText: {
    fontSize: fontSize.sm,
    fontWeight: '700',
    color: colors.textMuted,
  },
  authToggleTextActive: {
    color: colors.background,
  },
  visibilityButton: {
    position: 'absolute',
    right: spacing.sm,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
    paddingHorizontal: spacing.xs,
  },
  keySelectButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#0b0f13',
    borderRadius: borderRadius.lg,
    paddingVertical: 14,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
  },
  keySelectText: {
    flex: 1,
    fontSize: fontSize.md,
    color: colors.primary,
    fontWeight: '500',
  },
  advancedToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.sm,
    gap: spacing.sm,
    opacity: 0.6,
  },
  advancedToggleText: {
    fontSize: fontSize.sm,
    fontWeight: '500',
    color: colors.textMuted,
  },
  bottomSpacer: {
    height: 100,
  },
  bottomButtonContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: spacing.md,
    paddingBottom: spacing.xl,
    backgroundColor: 'transparent',
  },
  testButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.xl,
    gap: spacing.sm,
  },
  testButtonPressed: {
    backgroundColor: colors.primaryDark,
    transform: [{ scale: 0.98 }],
  },
  testButtonDisabled: {
    opacity: 0.5,
  },
  testButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.background,
    letterSpacing: -0.3,
  },
  errorText: {
    fontSize: fontSize.sm,
    color: colors.error,
    marginTop: spacing.xs,
    marginLeft: spacing.xs,
  },
  // Toggle styles for auto-reconnect
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  toggleLabelContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    flex: 1,
  },
  toggleLabel: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
  },
  toggleDescription: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    marginTop: 2,
  },
  toggleSwitch: {
    width: 48,
    height: 28,
    borderRadius: 14,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    padding: 2,
    justifyContent: 'center',
  },
  toggleSwitchActive: {
    backgroundColor: colors.primary,
  },
  toggleKnob: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: colors.textMuted,
  },
  toggleKnobActive: {
    backgroundColor: colors.background,
    alignSelf: 'flex-end',
  },
});
