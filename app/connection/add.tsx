/**
 * 接続追加画面
 */
import { useCallback, useState } from 'react';
import { Alert } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { useConnectionStore } from '@/stores/connectionStore';
import { ConnectionForm } from '@/components/connection/ConnectionForm';
import type { ConnectionInput } from '@/types/connection';

export default function AddConnectionScreen() {
  const router = useRouter();
  const addConnection = useConnectionStore((state) => state.addConnection);
  const [loading, setLoading] = useState(false);

  const handleSubmit = useCallback(
    async (values: ConnectionInput) => {
      setLoading(true);
      try {
        addConnection(values);
        router.back();
      } catch (error) {
        Alert.alert(
          'エラー',
          error instanceof Error ? error.message : '接続の追加に失敗しました'
        );
      } finally {
        setLoading(false);
      }
    },
    [addConnection, router]
  );

  return (
    <>
      <Stack.Screen
        options={{
          title: '新規接続',
          presentation: 'modal',
        }}
      />
      <ConnectionForm
        onSubmit={handleSubmit}
        onCancel={() => router.back()}
        submitLabel="追加"
        loading={loading}
      />
    </>
  );
}
