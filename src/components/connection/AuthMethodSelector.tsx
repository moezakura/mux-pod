/**
 * AuthMethodSelector
 *
 * パスワード認証/SSH鍵認証を切り替えるセレクタコンポーネント。
 */
import { memo } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';

import { colors, spacing, fontSize, borderRadius } from '@/theme';

export type AuthMethod = 'password' | 'key';

export interface AuthMethodSelectorProps {
  /** 選択中の認証方法 */
  value: AuthMethod;
  /** 認証方法が変更されたときのコールバック */
  onChange: (method: AuthMethod) => void;
  /** 無効化するか */
  disabled?: boolean;
}

export const AuthMethodSelector = memo(function AuthMethodSelector({
  value,
  onChange,
  disabled = false,
}: AuthMethodSelectorProps) {
  return (
    <View style={styles.container}>
      <Pressable
        style={[
          styles.option,
          value === 'password' && styles.optionActive,
          disabled && styles.optionDisabled,
        ]}
        onPress={() => !disabled && onChange('password')}
        disabled={disabled}
      >
        <MaterialCommunityIcons
          name="key-outline"
          size={18}
          color={value === 'password' ? colors.background : colors.textMuted}
        />
        <Text
          style={[
            styles.optionText,
            value === 'password' && styles.optionTextActive,
          ]}
        >
          Password
        </Text>
      </Pressable>

      <Pressable
        style={[
          styles.option,
          value === 'key' && styles.optionActive,
          disabled && styles.optionDisabled,
        ]}
        onPress={() => !disabled && onChange('key')}
        disabled={disabled}
      >
        <MaterialCommunityIcons
          name="key-variant"
          size={18}
          color={value === 'key' ? colors.background : colors.textMuted}
        />
        <Text
          style={[
            styles.optionText,
            value === 'key' && styles.optionTextActive,
          ]}
        >
          SSH Key
        </Text>
      </Pressable>
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    backgroundColor: 'rgba(0, 0, 0, 0.4)',
    padding: spacing.xs,
    borderRadius: borderRadius.lg,
  },
  option: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.md,
    gap: spacing.xs,
  },
  optionActive: {
    backgroundColor: colors.primary,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.3,
    shadowRadius: 5,
    elevation: 3,
  },
  optionDisabled: {
    opacity: 0.5,
  },
  optionText: {
    fontSize: fontSize.sm,
    fontWeight: '700',
    color: colors.textMuted,
  },
  optionTextActive: {
    color: colors.background,
  },
});
