/**
 * RuleTypeSelector
 *
 * ルールタイプ選択コンポーネント (TEXT/REGEX/IDLE/ANY)。
 * HTMLデザイン (notification_rules_setup.html) に完全準拠。
 */
import { memo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { colors, borderRadius, spacing, fontSize } from '@/theme';

export type ConditionType = 'TEXT' | 'REGEX' | 'IDLE' | 'ANY';

export interface RuleTypeSelectorProps {
  value: ConditionType;
  onChange: (type: ConditionType) => void;
}

const types: ConditionType[] = ['TEXT', 'REGEX', 'IDLE', 'ANY'];

export const RuleTypeSelector = memo(function RuleTypeSelector({
  value,
  onChange,
}: RuleTypeSelectorProps) {
  return (
    <View style={styles.container}>
      {types.map((type) => {
        const isActive = type === value;
        return (
          <Pressable
            key={type}
            style={[
              styles.button,
              isActive && styles.buttonActive,
            ]}
            onPress={() => onChange(type)}
          >
            <Text
              style={[
                styles.buttonText,
                isActive && styles.buttonTextActive,
              ]}
            >
              {type}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    backgroundColor: colors.background,
    borderRadius: borderRadius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: 4,
    gap: 4,
  },
  button: {
    flex: 1,
    paddingVertical: 6,
    borderRadius: borderRadius.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonActive: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 1,
  },
  buttonText: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textMuted,
  },
  buttonTextActive: {
    color: colors.text,
  },
});
