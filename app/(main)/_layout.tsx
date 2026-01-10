import { Stack } from 'expo-router';
import { colors } from '@/theme';

/**
 * メイン画面用のレイアウト（認証済みルート）
 */
export default function MainLayout() {
  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: {
          backgroundColor: colors.canvas,
        },
      }}
    />
  );
}
