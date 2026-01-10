/**
 * NotificationToggle
 *
 * 通知ルール用トグルスイッチ。
 * HTMLデザイン (notification_rules_setup.html) に完全準拠。
 */
import { memo } from 'react';
import { View, Pressable, StyleSheet, Animated } from 'react-native';
import { colors } from '@/theme';

export interface NotificationToggleProps {
  /** トグル状態 */
  value: boolean;
  /** 変更時のコールバック */
  onValueChange?: (value: boolean) => void;
  /** 無効状態 */
  disabled?: boolean;
}

export const NotificationToggle = memo(function NotificationToggle({
  value,
  onValueChange,
  disabled = false,
}: NotificationToggleProps) {
  const handlePress = () => {
    if (!disabled) {
      onValueChange?.(!value);
    }
  };

  return (
    <Pressable
      style={[
        styles.track,
        value && styles.trackActive,
        disabled && styles.trackDisabled,
      ]}
      onPress={handlePress}
      disabled={disabled}
      hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
    >
      <View
        style={[
          styles.thumb,
          value && styles.thumbActive,
        ]}
      />
    </Pressable>
  );
});

const styles = StyleSheet.create({
  track: {
    width: 36,
    height: 20,
    borderRadius: 10,
    backgroundColor: '#334155', // slate-700
    justifyContent: 'center',
    paddingHorizontal: 2,
  },
  trackActive: {
    backgroundColor: colors.primary,
  },
  trackDisabled: {
    opacity: 0.5,
  },
  thumb: {
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: '#d1d5db', // gray-300
  },
  thumbActive: {
    alignSelf: 'flex-end',
    borderColor: '#FFFFFF',
  },
});
