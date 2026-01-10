/**
 * SSH鍵インポート画面
 *
 * 秘密鍵ファイルを選択してインポートする画面。
 * パスフレーズ付き鍵にも対応。
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
  Modal,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { Stack, useRouter } from 'expo-router';
import * as DocumentPicker from 'expo-document-picker';
import * as FileSystem from 'expo-file-system';
import * as Clipboard from 'expo-clipboard';

import {
  importKey,
  validatePrivateKey,
  type ImportKeyResult,
} from '@/services/ssh/keyManager';
import { useKeyStore } from '@/stores/keyStore';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

type ImportStep = 'select' | 'configure' | 'success';

export default function ImportKeyScreen() {
  const router = useRouter();
  const addKey = useKeyStore((state) => state.addKey);

  const [step, setStep] = useState<ImportStep>('select');
  const [privateKey, setPrivateKey] = useState('');
  const [fileName, setFileName] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [passphrase, setPassphrase] = useState('');
  const [showPassphrase, setShowPassphrase] = useState(false);
  const [requireBiometrics, setRequireBiometrics] = useState(true);
  const [isEncrypted, setIsEncrypted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ImportKeyResult | null>(null);
  const [showPassphraseModal, setShowPassphraseModal] = useState(false);
  const [copied, setCopied] = useState(false);

  const handlePickFile = useCallback(async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: '*/*',
        copyToCacheDirectory: true,
      });

      if (result.canceled || !result.assets || result.assets.length === 0) {
        return;
      }

      const file = result.assets[0];
      if (!file || !file.uri) {
        setError('Failed to read file');
        return;
      }

      const content = await FileSystem.readAsStringAsync(file.uri);
      const validation = validatePrivateKey(content);

      if (!validation.valid) {
        setError(validation.error ?? 'Invalid private key file');
        return;
      }

      setPrivateKey(content);
      const filename = file.name ?? 'private_key';
      setFileName(filename);
      setIsEncrypted(validation.encrypted ?? false);
      setError(null);

      // Suggest a name based on the filename
      const suggestedName = filename
        .replace(/\.(pem|key|pub|txt)$/i, '')
        .replace(/[-_]/g, ' ');
      setName(suggestedName);

      setStep('configure');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to pick file');
    }
  }, []);

  const handlePasteKey = useCallback(async () => {
    try {
      const clipboardContent = await Clipboard.getStringAsync();
      if (!clipboardContent) {
        setError('Clipboard is empty');
        return;
      }

      const validation = validatePrivateKey(clipboardContent);
      if (!validation.valid) {
        setError(validation.error ?? 'Invalid private key in clipboard');
        return;
      }

      setPrivateKey(clipboardContent);
      setFileName('Pasted Key');
      setIsEncrypted(validation.encrypted ?? false);
      setError(null);
      setName('Imported Key');
      setStep('configure');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to read clipboard');
    }
  }, []);

  const handleImport = useCallback(async () => {
    if (!name.trim()) {
      setError('Key name is required');
      return;
    }

    if (isEncrypted && !passphrase) {
      setShowPassphraseModal(true);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const importResult = await importKey({
        name: name.trim(),
        privateKey,
        passphrase: isEncrypted ? passphrase : undefined,
        requireBiometrics,
      });

      setResult(importResult);
      addKey(importResult.key);
      setStep('success');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to import key');
    } finally {
      setLoading(false);
    }
  }, [name, privateKey, passphrase, isEncrypted, requireBiometrics, addKey]);

  const handlePassphraseSubmit = useCallback(() => {
    setShowPassphraseModal(false);
    handleImport();
  }, [handleImport]);

  const handleDone = useCallback(() => {
    router.back();
  }, [router]);

  const handleCopyPublicKey = useCallback(async () => {
    if (!result) return;

    await Clipboard.setStringAsync(result.publicKey);
    setCopied(true);

    setTimeout(() => {
      setCopied(false);
    }, 2000);
  }, [result]);

  const renderSelectStep = () => (
    <>
      <View style={styles.heroSection}>
        <View style={styles.heroIcon}>
          <MaterialCommunityIcons
            name="key-arrow-right"
            size={48}
            color={colors.primary}
          />
        </View>
        <Text style={styles.heroTitle}>Import Private Key</Text>
        <Text style={styles.heroSubtitle}>
          Select a private key file from your device or paste from clipboard.
        </Text>
      </View>

      <View style={styles.optionsContainer}>
        <Pressable
          style={({ pressed }) => [
            styles.optionCard,
            pressed && styles.optionCardPressed,
          ]}
          onPress={handlePickFile}
        >
          <View style={styles.optionIconContainer}>
            <MaterialCommunityIcons
              name="file-key-outline"
              size={32}
              color={colors.primary}
            />
          </View>
          <View style={styles.optionContent}>
            <Text style={styles.optionTitle}>Choose File</Text>
            <Text style={styles.optionDescription}>
              Select a .pem, .key, or OpenSSH key file
            </Text>
          </View>
          <MaterialCommunityIcons
            name="chevron-right"
            size={24}
            color={colors.textMuted}
          />
        </Pressable>

        <Pressable
          style={({ pressed }) => [
            styles.optionCard,
            pressed && styles.optionCardPressed,
          ]}
          onPress={handlePasteKey}
        >
          <View style={styles.optionIconContainer}>
            <MaterialCommunityIcons
              name="clipboard-text-outline"
              size={32}
              color={colors.primary}
            />
          </View>
          <View style={styles.optionContent}>
            <Text style={styles.optionTitle}>Paste from Clipboard</Text>
            <Text style={styles.optionDescription}>
              Paste a private key copied to clipboard
            </Text>
          </View>
          <MaterialCommunityIcons
            name="chevron-right"
            size={24}
            color={colors.textMuted}
          />
        </Pressable>
      </View>

      {error && (
        <View style={styles.errorContainer}>
          <MaterialCommunityIcons
            name="alert-circle"
            size={20}
            color={colors.error}
          />
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      <View style={styles.infoBox}>
        <MaterialCommunityIcons
          name="shield-check"
          size={20}
          color={colors.primary}
        />
        <Text style={styles.infoText}>
          Your private key is stored securely on device using the system keychain.
          It never leaves your device.
        </Text>
      </View>
    </>
  );

  const renderConfigureStep = () => (
    <>
      {/* Selected File Info */}
      <View style={styles.selectedFileCard}>
        <MaterialCommunityIcons
          name="file-key"
          size={24}
          color={colors.success}
        />
        <View style={styles.selectedFileInfo}>
          <Text style={styles.selectedFileName}>{fileName}</Text>
          {isEncrypted && (
            <View style={styles.encryptedBadge}>
              <MaterialCommunityIcons
                name="lock"
                size={12}
                color={colors.warning}
              />
              <Text style={styles.encryptedBadgeText}>Encrypted</Text>
            </View>
          )}
        </View>
        <Pressable
          style={styles.changeFileButton}
          onPress={() => {
            setStep('select');
            setPrivateKey('');
            setFileName(null);
            setError(null);
          }}
        >
          <Text style={styles.changeFileText}>Change</Text>
        </Pressable>
      </View>

      {/* Key Name Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>KEY NAME</Text>
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
              onChangeText={(text) => {
                setName(text);
                setError(null);
              }}
              placeholder="e.g. Work Server, Personal VPS"
              placeholderTextColor={colors.textMuted}
              autoCapitalize="words"
            />
          </View>
          {error && <Text style={styles.inputError}>{error}</Text>}
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
  );

  const renderSuccessStep = () => (
    <View style={styles.successContainer}>
      <View style={styles.successIconContainer}>
        <MaterialCommunityIcons
          name="check-circle"
          size={64}
          color={colors.success}
        />
      </View>

      <Text style={styles.successTitle}>Key Imported Successfully</Text>
      <Text style={styles.successSubtitle}>
        Your private key has been securely stored on your device.
      </Text>

      {result && (
        <>
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
                {copied ? 'Copied!' : 'Copy Public Key'}
              </Text>
            </Pressable>
          </View>
        </>
      )}
    </View>
  );

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      <Stack.Screen
        options={{
          title: 'Import Key',
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
          {step === 'success' ? 'Key Imported' : 'Import Key'}
        </Text>
        {step === 'success' ? (
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
          {step === 'select' && renderSelectStep()}
          {step === 'configure' && renderConfigureStep()}
          {step === 'success' && renderSuccessStep()}
        </ScrollView>
      </KeyboardAvoidingView>

      {/* Import Button (only shown in configure step) */}
      {step === 'configure' && (
        <View style={styles.bottomButtonContainer}>
          <Pressable
            style={({ pressed }) => [
              styles.importButton,
              pressed && styles.importButtonPressed,
              loading && styles.importButtonDisabled,
            ]}
            onPress={handleImport}
            disabled={loading}
          >
            <MaterialCommunityIcons
              name="key-plus"
              size={20}
              color={colors.background}
            />
            <Text style={styles.importButtonText}>
              {loading ? 'IMPORTING...' : 'IMPORT KEY'}
            </Text>
          </Pressable>
        </View>
      )}

      {/* Passphrase Modal */}
      <Modal
        visible={showPassphraseModal}
        transparent
        animationType="fade"
        onRequestClose={() => setShowPassphraseModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <MaterialCommunityIcons
                name="lock"
                size={32}
                color={colors.warning}
              />
              <Text style={styles.modalTitle}>Enter Passphrase</Text>
              <Text style={styles.modalSubtitle}>
                This key is encrypted. Please enter the passphrase to decrypt it.
              </Text>
            </View>

            <View style={styles.modalInputContainer}>
              <TextInput
                style={styles.modalInput}
                value={passphrase}
                onChangeText={setPassphrase}
                placeholder="Enter passphrase"
                placeholderTextColor={colors.textMuted}
                secureTextEntry={!showPassphrase}
                autoFocus
              />
              <Pressable
                style={styles.visibilityButton}
                onPress={() => setShowPassphrase(!showPassphrase)}
              >
                <MaterialCommunityIcons
                  name={showPassphrase ? 'eye-outline' : 'eye-off-outline'}
                  size={20}
                  color={colors.textMuted}
                />
              </Pressable>
            </View>

            <View style={styles.modalButtons}>
              <Pressable
                style={styles.modalCancelButton}
                onPress={() => {
                  setShowPassphraseModal(false);
                  setPassphrase('');
                }}
              >
                <Text style={styles.modalCancelText}>Cancel</Text>
              </Pressable>
              <Pressable
                style={[
                  styles.modalConfirmButton,
                  !passphrase && styles.modalConfirmButtonDisabled,
                ]}
                onPress={handlePassphraseSubmit}
                disabled={!passphrase}
              >
                <Text style={styles.modalConfirmText}>Decrypt</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
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
  // Select Step Styles
  heroSection: {
    alignItems: 'center',
    paddingVertical: spacing.xl,
  },
  heroIcon: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.lg,
  },
  heroTitle: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.text,
    marginBottom: spacing.sm,
  },
  heroSubtitle: {
    fontSize: fontSize.md,
    color: colors.textSecondary,
    textAlign: 'center',
    paddingHorizontal: spacing.lg,
  },
  optionsContainer: {
    gap: spacing.md,
    marginBottom: spacing.lg,
  },
  optionCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1c242b',
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.05)',
    gap: spacing.md,
  },
  optionCardPressed: {
    backgroundColor: '#252d35',
  },
  optionIconContainer: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  optionContent: {
    flex: 1,
  },
  optionTitle: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 2,
  },
  optionDescription: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  errorContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(239, 68, 68, 0.1)',
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  errorText: {
    flex: 1,
    fontSize: fontSize.sm,
    color: colors.error,
  },
  infoBox: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    backgroundColor: 'rgba(0, 192, 209, 0.05)',
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    gap: spacing.sm,
    borderWidth: 1,
    borderColor: 'rgba(0, 192, 209, 0.1)',
  },
  infoText: {
    flex: 1,
    fontSize: fontSize.sm,
    color: colors.textSecondary,
    lineHeight: 20,
  },
  // Configure Step Styles
  selectedFileCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(34, 197, 94, 0.1)',
    borderRadius: borderRadius.xl,
    padding: spacing.md,
    gap: spacing.md,
    marginBottom: spacing.lg,
    borderWidth: 1,
    borderColor: 'rgba(34, 197, 94, 0.2)',
  },
  selectedFileInfo: {
    flex: 1,
  },
  selectedFileName: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
  },
  encryptedBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginTop: 4,
  },
  encryptedBadgeText: {
    fontSize: fontSize.xs,
    color: colors.warning,
    fontWeight: '500',
  },
  changeFileButton: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
  },
  changeFileText: {
    fontSize: fontSize.sm,
    color: colors.primary,
    fontWeight: '600',
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
  inputError: {
    fontSize: fontSize.sm,
    color: colors.error,
    marginTop: spacing.sm,
    marginLeft: spacing.xs,
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
  importButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.xl,
    gap: spacing.sm,
  },
  importButtonPressed: {
    backgroundColor: colors.primaryDark,
    transform: [{ scale: 0.98 }],
  },
  importButtonDisabled: {
    opacity: 0.5,
  },
  importButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.background,
    letterSpacing: -0.3,
  },
  // Success Step Styles
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
  // Modal Styles
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
  },
  modalContent: {
    backgroundColor: '#1c242b',
    borderRadius: borderRadius.xl,
    padding: spacing.lg,
    width: '100%',
    maxWidth: 400,
  },
  modalHeader: {
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  modalTitle: {
    fontSize: fontSize.xl,
    fontWeight: '700',
    color: colors.text,
    marginTop: spacing.md,
    marginBottom: spacing.sm,
  },
  modalSubtitle: {
    fontSize: fontSize.sm,
    color: colors.textSecondary,
    textAlign: 'center',
  },
  modalInputContainer: {
    position: 'relative',
    marginBottom: spacing.lg,
  },
  modalInput: {
    backgroundColor: '#0b0f13',
    borderRadius: borderRadius.lg,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
    paddingRight: 48,
    fontSize: fontSize.md,
    color: colors.text,
  },
  visibilityButton: {
    position: 'absolute',
    right: spacing.sm,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
    paddingHorizontal: spacing.xs,
  },
  modalButtons: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  modalCancelButton: {
    flex: 1,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    alignItems: 'center',
  },
  modalCancelText: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  modalConfirmButton: {
    flex: 1,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    backgroundColor: colors.primary,
    alignItems: 'center',
  },
  modalConfirmButtonDisabled: {
    opacity: 0.5,
  },
  modalConfirmText: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.background,
  },
});
