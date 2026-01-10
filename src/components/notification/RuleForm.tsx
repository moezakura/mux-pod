/**
 * RuleForm
 *
 * 新規ルール作成フォームコンポーネント。
 * HTMLデザイン (notification_rules_setup.html) に完全準拠。
 */
import { memo, useState, useCallback } from 'react';
import { View, Text, TextInput, Pressable, StyleSheet } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { colors, borderRadius, spacing, fontSize, shadows } from '@/theme';
import { RuleTypeSelector, type ConditionType } from './RuleTypeSelector';

export interface RuleFormData {
  type: ConditionType;
  pattern: string;
  frequency: 'once' | 'every';
  action: 'push' | 'silent';
}

export interface RuleFormProps {
  onSave?: (data: RuleFormData) => void;
  onCancel?: () => void;
}

export const RuleForm = memo(function RuleForm({
  onSave,
  onCancel,
}: RuleFormProps) {
  const [type, setType] = useState<ConditionType>('TEXT');
  const [pattern, setPattern] = useState('segmentation_fault');
  const [frequency, setFrequency] = useState<'once' | 'every'>('once');
  const [action, setAction] = useState<'push' | 'silent'>('push');
  const [isValidRegex, setIsValidRegex] = useState(true);

  const handlePatternChange = useCallback((text: string) => {
    setPattern(text);
    // Validate regex if in REGEX mode
    if (type === 'REGEX') {
      try {
        new RegExp(text);
        setIsValidRegex(true);
      } catch {
        setIsValidRegex(false);
      }
    } else {
      setIsValidRegex(true);
    }
  }, [type]);

  const handleSave = useCallback(() => {
    onSave?.({
      type,
      pattern,
      frequency,
      action,
    });
  }, [type, pattern, frequency, action, onSave]);

  const showPatternInput = type === 'TEXT' || type === 'REGEX';
  const showIdleInput = type === 'IDLE';

  return (
    <View style={styles.container}>
      {/* Tech decoration */}
      <View style={styles.decorationIcon}>
        <MaterialCommunityIcons
          name="cog-outline"
          size={64}
          color={colors.textDim}
          style={{ opacity: 0.1, transform: [{ rotate: '12deg' }] }}
        />
      </View>

      {/* Header */}
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <View style={styles.pulseDot} />
          <Text style={styles.headerTitle}>New Rule Configuration</Text>
        </View>
        <Text style={styles.draftLabel}>DRAFT</Text>
      </View>

      {/* Type Selector */}
      <RuleTypeSelector value={type} onChange={setType} />

      {/* Input Area */}
      <View style={styles.inputArea}>
        {showPatternInput && (
          <View style={styles.patternInputContainer}>
            <Text style={styles.inputLabel}>MATCH PATTERN</Text>
            <View style={styles.patternWrapper}>
              <Text style={styles.patternPrefix}>/</Text>
              <TextInput
                style={styles.patternInput}
                value={pattern}
                onChangeText={handlePatternChange}
                placeholder="Enter pattern..."
                placeholderTextColor={colors.textDim}
                autoCapitalize="none"
                autoCorrect={false}
              />
              <Text style={styles.patternSuffix}>/i</Text>
              {/* Ping indicator */}
              <View style={styles.pingContainer}>
                <View style={styles.pingOuter} />
                <View style={styles.pingInner} />
              </View>
            </View>
          </View>
        )}

        {showIdleInput && (
          <View style={styles.patternInputContainer}>
            <Text style={styles.inputLabel}>IDLE TIMEOUT (seconds)</Text>
            <TextInput
              style={styles.textInput}
              value={pattern}
              onChangeText={setPattern}
              placeholder="300"
              placeholderTextColor={colors.textDim}
              keyboardType="numeric"
            />
          </View>
        )}

        {/* Settings Grid */}
        <View style={styles.settingsGrid}>
          <View style={styles.settingItem}>
            <Text style={styles.settingLabel}>FREQUENCY</Text>
            <Pressable
              style={styles.selectButton}
              onPress={() => setFrequency(frequency === 'once' ? 'every' : 'once')}
            >
              <Text style={styles.selectText}>
                {frequency === 'once' ? 'Once per session' : 'Every occurrence'}
              </Text>
              <MaterialCommunityIcons
                name="chevron-down"
                size={16}
                color={colors.textMuted}
              />
            </Pressable>
          </View>

          <View style={styles.settingItem}>
            <Text style={styles.settingLabel}>ACTION</Text>
            <Pressable
              style={styles.selectButton}
              onPress={() => setAction(action === 'push' ? 'silent' : 'push')}
            >
              <Text style={styles.selectText}>
                {action === 'push' ? 'Push Notification' : 'Silent Log'}
              </Text>
              <MaterialCommunityIcons
                name="chevron-down"
                size={16}
                color={colors.textMuted}
              />
            </Pressable>
          </View>
        </View>

        {/* Test Button & Validation */}
        <View style={styles.testRow}>
          <Pressable style={styles.testButton}>
            <MaterialCommunityIcons
              name="play"
              size={16}
              color={colors.primary}
            />
            <Text style={styles.testButtonText}>Test Pattern</Text>
          </Pressable>

          {type === 'REGEX' && (
            <View style={styles.validationStatus}>
              <MaterialCommunityIcons
                name={isValidRegex ? 'check' : 'close'}
                size={12}
                color={isValidRegex ? colors.emerald500 : colors.error}
              />
              <Text
                style={[
                  styles.validationText,
                  { color: isValidRegex ? colors.emerald500 : colors.error },
                ]}
              >
                {isValidRegex ? 'Valid Regex' : 'Invalid Regex'}
              </Text>
            </View>
          )}
        </View>
      </View>

      {/* Action Buttons */}
      <View style={styles.actions}>
        <Pressable
          style={({ pressed }) => [
            styles.cancelButton,
            pressed && styles.buttonPressed,
          ]}
          onPress={onCancel}
        >
          <Text style={styles.cancelButtonText}>Cancel</Text>
        </Pressable>

        <Pressable
          style={({ pressed }) => [
            styles.saveButton,
            pressed && styles.saveButtonPressed,
          ]}
          onPress={handleSave}
        >
          <MaterialCommunityIcons
            name="content-save"
            size={20}
            color="#000000"
          />
          <Text style={styles.saveButtonText}>Save Rule</Text>
        </Pressable>
      </View>
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.surfaceDarker,
    borderRadius: borderRadius.xl,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg - 4, // p-5 = 20px
    position: 'relative',
    overflow: 'hidden',
    ...shadows.card,
  },
  decorationIcon: {
    position: 'absolute',
    top: 0,
    right: 0,
    padding: spacing.sm,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.md,
    zIndex: 10,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  pulseDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.primary,
  },
  headerTitle: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.text,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  draftLabel: {
    fontSize: fontSize.xs,
    fontFamily: 'monospace',
    color: colors.textMuted,
  },
  inputArea: {
    marginTop: spacing.md,
    gap: spacing.md,
  },
  patternInputContainer: {
    gap: 4,
  },
  inputLabel: {
    fontSize: fontSize.xs,
    fontFamily: 'monospace',
    color: colors.primary,
    marginBottom: 4,
  },
  patternWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: borderRadius.md,
    paddingHorizontal: spacing.sm + 4,
    paddingVertical: spacing.sm + 2,
  },
  patternPrefix: {
    fontFamily: 'monospace',
    color: colors.textMuted,
    fontSize: fontSize.md,
  },
  patternInput: {
    flex: 1,
    fontFamily: 'monospace',
    fontSize: fontSize.md,
    color: colors.text,
    paddingHorizontal: 4,
    paddingVertical: 0,
  },
  patternSuffix: {
    fontFamily: 'monospace',
    color: colors.textMuted,
    fontSize: fontSize.md,
    marginRight: spacing.lg,
  },
  pingContainer: {
    position: 'absolute',
    right: 40,
    top: '50%',
    marginTop: -4,
  },
  pingOuter: {
    position: 'absolute',
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.primary,
    opacity: 0.5,
  },
  pingInner: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.primary,
  },
  textInput: {
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: borderRadius.md,
    paddingHorizontal: spacing.sm + 4,
    paddingVertical: spacing.sm + 2,
    fontFamily: 'monospace',
    fontSize: fontSize.md,
    color: colors.text,
  },
  settingsGrid: {
    flexDirection: 'row',
    gap: spacing.sm + 4, // gap-3
  },
  settingItem: {
    flex: 1,
    gap: 4,
  },
  settingLabel: {
    fontSize: fontSize.xs,
    fontFamily: 'monospace',
    color: colors.textMuted,
    marginBottom: 4,
  },
  selectButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: borderRadius.md,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.sm,
  },
  selectText: {
    fontSize: fontSize.sm,
    color: colors.text,
    flex: 1,
  },
  testRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: spacing.sm,
  },
  testButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  testButtonText: {
    fontSize: fontSize.sm,
    fontFamily: 'monospace',
    color: colors.primary,
  },
  validationStatus: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  validationText: {
    fontSize: fontSize.xs,
    fontFamily: 'monospace',
  },
  actions: {
    flexDirection: 'row',
    gap: spacing.sm + 4, // gap-3
    marginTop: spacing.lg - 4, // mt-5
  },
  cancelButton: {
    flex: 1,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    paddingVertical: spacing.sm + 4, // py-3
    borderRadius: borderRadius.lg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cancelButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.text,
  },
  saveButton: {
    flex: 2,
    flexDirection: 'row',
    backgroundColor: colors.primary,
    paddingVertical: spacing.sm + 4, // py-3
    borderRadius: borderRadius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
    ...shadows.glow,
  },
  saveButtonPressed: {
    backgroundColor: colors.primaryDark,
  },
  saveButtonText: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: '#000000',
  },
  buttonPressed: {
    opacity: 0.8,
  },
});
