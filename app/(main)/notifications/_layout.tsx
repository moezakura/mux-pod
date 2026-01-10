import { Stack } from 'expo-router';
import { colors } from '@/theme';

/**
 * 通知画面用のレイアウト
 */
export default function NotificationsLayout() {
  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: {
          backgroundColor: colors.background,
        },
      }}
    />
  );
}
