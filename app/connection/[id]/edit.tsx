/**
 * 接続編集画面
 */
import { useCallback, useState } from 'react';
import { View, Text, StyleSheet, Alert } from 'react-native';
import { Stack, useRouter, useLocalSearchParams } from 'expo-router';
import { useConnectionStore } from '@/stores/connectionStore';
import { ConnectionForm } from '@/components/connection/ConnectionForm';
import type { ConnectionInput } from '@/types/connection';

export default function EditConnectionScreen() {
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();

  const connection = useConnectionStore((state) =>
    state.connections.find((c) => c.id === id)
  );
  const updateConnection = useConnectionStore((state) => state.updateConnection);

  const [loading, setLoading] = useState(false);

  const handleSubmit = useCallback(
    async (values: ConnectionInput) => {
      if (!id) return;

      setLoading(true);
      try {
        updateConnection(id, values);
        router.back();
      } catch (error) {
        Alert.alert(
          'エラー',
          error instanceof Error ? error.message : '接続の更新に失敗しました'
        );
      } finally {
        setLoading(false);
      }
    },
    [id, updateConnection, router]
  );

  if (!connection) {
    return (
      <>
        <Stack.Screen
          options={{
            title: '接続編集',
            presentation: 'modal',
          }}
        />
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>接続が見つかりません</Text>
        </View>
      </>
    );
  }

  return (
    <>
      <Stack.Screen
        options={{
          title: '接続編集',
          presentation: 'modal',
        }}
      />
      <ConnectionForm
        initialValues={connection}
        onSubmit={handleSubmit}
        onCancel={() => router.back()}
        submitLabel="保存"
        loading={loading}
      />
    </>
  );
}

const styles = StyleSheet.create({
  errorContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#282A36',
  },
  errorText: {
    fontSize: 16,
    color: '#FF5555',
  },
});
