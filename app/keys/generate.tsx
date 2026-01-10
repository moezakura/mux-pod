/**
 * SSH鍵生成画面
 *
 * ED25519鍵ペアを生成し、公開鍵を表示・コピーする画面。
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
import { Stack, useRouter } from 'expo-router';
import * as Clipboard from 'expo-clipboard';

import { generateKey, type GenerateKeyResult } from '@/services/ssh/keyManager';
import { useKeyStore } from '@/stores/keyStore';
import { colors, spacing, fontSize, borderRadius } from '@/theme';
import type { SSHKeyType } from '@/types/sshKey';

const KEY_TYPES: { value: SSHKeyType; label: string; description: string }[] = [
  { value: 'ed25519', label: 'ED25519', description: 'Recommended - Fast & Secure' },
  { value: 'rsa-4096', label: 'RSA-4096', description: 'Wide compatibility' },
  { value: 'ecdsa', label: 'ECDSA', description: 'NIST P-256 curve' },
];

export default function GenerateKeyScreen() {
  const router = useRouter();
  const addKey = useKeyStore((state) => state.addKey);

  const [name, setName] = useState('');
  const [keyType, setKeyType] = useState<SSHKeyType>('ed25519');
  const [requireBiometrics, setRequireBiometrics] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<GenerateKeyResult | null>(null);
  const [copied, setCopied] = useState(false);

  const handleGenerate = useCallback(async () => {
    if (!name.trim()) {
      setError('Key name is required');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const generatedResult = await generateKey({
        name: name.trim(),
        keyType,
        requireBiometrics,
      });
      setResult(generatedResult);
      addKey(generatedResult.key);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to generate key');
    } finally {
      setLoading(false);
    }
  }, [name, keyType, requireBiometrics, addKey]);

  const handleCopyPublicKey = useCallback(async () => {
    if (!result) return;

    await Clipboard.setStringAsync(result.publicKey);
    setCopied(true);

    setTimeout(() => {
      setCopied(false);
    }, 2000);
  }, [result]);

  const handleDone = useCallback(() => {
    router.back();
  }, [router]);

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      <Stack.Screen
        options={{
          title: 'Generate Key',
          presentation: 'modal',
          headerShown: false,
        }}
      />

      {/* Header */}
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} style={styles.headerButton}>
          <Text style={styles.headerButtonText}>Cancel</Text>
        </Pressable>
        <Text style={styles.headerTitle}>
          {result ? 'Key Generated' : 'Generate Key'}
        </Text>
        {result ? (
          <Pressable onPress={handleDone} style={styles.headerButton}>
            <Text style={[styles.headerButtonText, styles.headerSaveText]}>Done</Text>
          </Pressable>
        ) : (
          <View style={styles.headerButton} />
        )}
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
          {result ? (
            /* Success State - Show Public Key */
            <View style={styles.successContainer}>
              {/* Success Icon */}
              <View style={styles.successIconContainer}>
                <MaterialCommunityIcons
                  name="check-circle"
                  size={64}
                  color={colors.success}
                />
              </View>

              <Text style={styles.successTitle}>Key Generated Successfully</Text>
              <Text style={styles.successSubtitle}>
                Copy the public key below and add it to your server&apos;s authorized_keys file.
              </Text>

              {/* Key Info Card */}
              <View style={styles.keyInfoCard}>
                <View style={styles.keyInfoRow}>
                  <Text style={styles.keyInfoLabel}>Name</Text>
                  <Text style={styles.keyInfoValue}>{result.key.name}</Text>
                </View>
                <View style={styles.separator} />
                <View style={styles.keyInfoRow}>
                  <Text style={styles.keyInfoLabel}>Type</Text>
                  <Text style={styles.keyInfoValue}>{result.key.keyType.toUpperCase()}</Text>
                </View>
                <View style={styles.separator} />
                <View style={styles.keyInfoRow}>
                  <Text style={styles.keyInfoLabel}>Fingerprint</Text>
                  <Text style={[styles.keyInfoValue, styles.monoText]} numberOfLines={1}>
                    {result.key.fingerprint}
                  </Text>
                </View>
              </View>

              {/* Public Key Section */}
              <View style={styles.publicKeySection}>
                <Text style={styles.publicKeyLabel}>PUBLIC KEY</Text>
                <View style={styles.publicKeyCard}>
                  <Text style={styles.publicKeyText} selectable>
                    {result.publicKey}
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
                    {copied ? 'Copied!' : 'Copy to Clipboard'}
                  </Text>
                </Pressable>
              </View>
            </View>
          ) : (
            /* Form State */
            <>
              {/* Key Name Section */}
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>KEY NAME</Text>
                <View style={styles.sectionCard}>
                  <View style={styles.inputContainer}>
                    <View style={styles.inputIconContainer}>
                      <MaterialCommunityIcons
                        name="key-variant"
                        size={20}
                        color={colors.textMuted}
                      />
                    </View>
                    <TextInput
                      style={styles.inputWithIcon}
                      value={name}
                      onChangeText={(text) => {
                        setName(text);
                        setError(null);
                      }}
                      placeholder="e.g. Work Server, Personal VPS"
                      placeholderTextColor={colors.textMuted}
                      autoCapitalize="words"
                      autoFocus
                    />
                  </View>
                  {error && <Text style={styles.errorText}>{error}</Text>}
                </View>
              </View>

              {/* Key Type Section */}
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>KEY TYPE</Text>
                <View style={styles.sectionCard}>
                  {KEY_TYPES.map((type, index) => (
                    <Pressable
                      key={type.value}
                      style={[
                        styles.keyTypeOption,
                        keyType === type.value && styles.keyTypeOptionActive,
                        index > 0 && styles.keyTypeOptionBorder,
                      ]}
                      onPress={() => setKeyType(type.value)}
                    >
                      <View style={styles.keyTypeInfo}>
                        <Text
                          style={[
                            styles.keyTypeLabel,
                            keyType === type.value && styles.keyTypeLabelActive,
                          ]}
                        >
                          {type.label}
                        </Text>
                        <Text style={styles.keyTypeDescription}>{type.description}</Text>
                      </View>
                      <View
                        style={[
                          styles.radioOuter,
                          keyType === type.value && styles.radioOuterActive,
                        ]}
                      >
                        {keyType === type.value && <View style={styles.radioInner} />}
                      </View>
                    </Pressable>
                  ))}
                </View>
              </View>

              {/* Security Options Section */}
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>SECURITY OPTIONS</Text>
                <View style={styles.sectionCard}>
                  <Pressable
                    style={styles.toggleRow}
                    onPress={() => setRequireBiometrics(!requireBiometrics)}
                  >
                    <View style={styles.toggleInfo}>
                      <MaterialCommunityIcons
                        name="fingerprint"
                        size={24}
                        color={requireBiometrics ? colors.primary : colors.textMuted}
                      />
                      <View style={styles.toggleTextContainer}>
                        <Text style={styles.toggleLabel}>Require Biometrics</Text>
                        <Text style={styles.toggleDescription}>
                          Use fingerprint/face to access this key
                        </Text>
                      </View>
                    </View>
                    <View
                      style={[
                        styles.toggle,
                        requireBiometrics && styles.toggleActive,
                      ]}
                    >
                      <View
                        style={[
                          styles.toggleKnob,
                          requireBiometrics && styles.toggleKnobActive,
                        ]}
                      />
                    </View>
                  </Pressable>
                </View>
              </View>
            </>
          )}
        </ScrollView>
      </KeyboardAvoidingView>

      {/* Generate Button (only shown when not generated) */}
      {!result && (
        <View style={styles.bottomButtonContainer}>
          <Pressable
            style={({ pressed }) => [
              styles.generateButton,
              pressed && styles.generateButtonPressed,
              loading && styles.generateButtonDisabled,
            ]}
            onPress={handleGenerate}
            disabled={loading}
          >
            <MaterialCommunityIcons
              name="key-plus"
              size={20}
              color={colors.background}
            />
            <Text style={styles.generateButtonText}>
              {loading ? 'GENERATING...' : 'GENERATE KEY'}
            </Text>
          </Pressable>
        </View>
      )}
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
    minWidth: 60,
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
  sectionTitle: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    letterSpacing: 1.5,
    color: colors.textMuted,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    paddingHorizontal: spacing.xs,
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
  errorText: {
    fontSize: fontSize.sm,
    color: colors.error,
    marginTop: spacing.sm,
    marginLeft: spacing.xs,
  },
  keyTypeOption: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.sm,
  },
  keyTypeOptionActive: {
    backgroundColor: 'rgba(0, 192, 209, 0.05)',
    marginHorizontal: -spacing.md,
    paddingHorizontal: spacing.md + spacing.sm,
    borderRadius: borderRadius.lg,
  },
  keyTypeOptionBorder: {
    borderTopWidth: 1,
    borderTopColor: 'rgba(255, 255, 255, 0.05)',
  },
  keyTypeInfo: {
    flex: 1,
  },
  keyTypeLabel: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 2,
  },
  keyTypeLabelActive: {
    color: colors.primary,
  },
  keyTypeDescription: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  radioOuter: {
    width: 22,
    height: 22,
    borderRadius: 11,
    borderWidth: 2,
    borderColor: colors.textMuted,
    alignItems: 'center',
    justifyContent: 'center',
  },
  radioOuterActive: {
    borderColor: colors.primary,
  },
  radioInner: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: colors.primary,
  },
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: spacing.sm,
  },
  toggleInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    gap: spacing.md,
  },
  toggleTextContainer: {
    flex: 1,
  },
  toggleLabel: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 2,
  },
  toggleDescription: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  toggle: {
    width: 52,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#0b0f13',
    padding: 3,
  },
  toggleActive: {
    backgroundColor: colors.primary,
  },
  toggleKnob: {
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: colors.textMuted,
  },
  toggleKnobActive: {
    backgroundColor: colors.background,
    transform: [{ translateX: 20 }],
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
  generateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.xl,
    gap: spacing.sm,
  },
  generateButtonPressed: {
    backgroundColor: colors.primaryDark,
    transform: [{ scale: 0.98 }],
  },
  generateButtonDisabled: {
    opacity: 0.5,
  },
  generateButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.background,
    letterSpacing: -0.3,
  },
  // Success State Styles
  successContainer: {
    alignItems: 'center',
    paddingTop: spacing.lg,
  },
  successIconContainer: {
    marginBottom: spacing.lg,
  },
  successTitle: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.text,
    marginBottom: spacing.sm,
    textAlign: 'center',
  },
  successSubtitle: {
    fontSize: fontSize.md,
    color: colors.textSecondary,
    textAlign: 'center',
    marginBottom: spacing.xl,
    paddingHorizontal: spacing.lg,
  },
  keyInfoCard: {
    backgroundColor: '#1c242b',
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.05)',
    width: '100%',
    marginBottom: spacing.lg,
  },
  keyInfoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.sm,
  },
  keyInfoLabel: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    fontWeight: '500',
  },
  keyInfoValue: {
    fontSize: fontSize.md,
    color: colors.text,
    fontWeight: '600',
    flex: 1,
    textAlign: 'right',
    marginLeft: spacing.md,
  },
  monoText: {
    fontFamily: 'monospace',
    fontSize: fontSize.sm,
  },
  separator: {
    height: 1,
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  publicKeySection: {
    width: '100%',
  },
  publicKeyLabel: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    letterSpacing: 1.5,
    color: colors.textMuted,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    paddingHorizontal: spacing.xs,
  },
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
});
