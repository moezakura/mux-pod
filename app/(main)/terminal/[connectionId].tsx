/**
 * ターミナル画面
 *
 * 接続先のtmuxセッション/ウィンドウ/ペインを表示・操作する。
 * デザインガイドラインに準拠したターミナルUI。
 */
import { useEffect, useCallback, useState, useMemo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useSSH } from '@/hooks/useSSH';
import { useTmux } from '@/hooks/useTmux';
import { useTerminal } from '@/hooks/useTerminal';
import { useReconnectDialog } from '@/hooks/useReconnectDialog';
import { useConnectionStore } from '@/stores/connectionStore';
import {
  TerminalView,
  TerminalInput,
  SpecialKeys,
  TerminalHeader,
} from '@/components/terminal';
import { ReconnectDialog } from '@/components/connection';
import { colors, spacing, fontSize } from '@/theme';

export default function TerminalScreen() {
  const { connectionId } = useLocalSearchParams<{ connectionId: string }>();
  const router = useRouter();
  const [keyboardVisible, setKeyboardVisible] = useState(false);
  const [latency, setLatency] = useState<number | undefined>(undefined);

  // SSH接続
  const {
    client,
    connect,
    disconnect,
    isConnected,
    isConnecting,
    error: sshError,
  } = useSSH();

  // tmuxセッション管理
  const {
    sessions,
    selectedSession,
    selectedWindow,
    selectedPane,
    selectSession,
    selectWindow,
    currentSession,
    loading: tmuxLoading,
    error: tmuxError,
  } = useTmux(client, connectionId ?? '');

  // ターミナル表示
  const { lines, sendKeys, sendSpecialKey, sendCtrl } = useTerminal(
    client,
    selectedSession,
    selectedWindow,
    selectedPane
  );

  // 接続情報を取得
  const connection = useConnectionStore((state) =>
    state.connections.find((c) => c.id === connectionId)
  );

  // 再接続ダイアログ
  const {
    isVisible: reconnectVisible,
    connectionState,
    reconnect,
    cancel: cancelReconnect,
    retry,
    hide: hideReconnect,
  } = useReconnectDialog(connection!, client!);

  // 接続を開始
  useEffect(() => {
    if (connectionId && !isConnected && !isConnecting) {
      const startTime = Date.now();
      connect(connectionId)
        .then(() => {
          setLatency(Date.now() - startTime);
        })
        .catch(console.error);
    }
  }, [connectionId, isConnected, isConnecting, connect]);

  // 切断時にホームに戻る
  useEffect(() => {
    return () => {
      disconnect();
    };
  }, [disconnect]);

  // セッション選択ハンドラ（セッション変更時はウィンドウ0を選択）
  const handleSessionSelect = useCallback(
    (name: string) => {
      selectSession(name);
    },
    [selectSession]
  );

  // ウィンドウ選択ハンドラ
  const handleWindowSelect = useCallback(
    (index: number) => {
      selectWindow(index);
    },
    [selectWindow]
  );

  // キー送信ハンドラ
  const handleSendKeys = useCallback(
    async (keys: string) => {
      await sendKeys(keys);
    },
    [sendKeys]
  );

  const handleSendSpecialKey = useCallback(
    async (key: string) => {
      await sendSpecialKey(key);
    },
    [sendSpecialKey]
  );

  const handleSendCtrl = useCallback(
    async (key: string) => {
      await sendCtrl(key);
    },
    [sendCtrl]
  );

  // キーボード表示状態
  const handleInputFocus = useCallback(() => {
    setKeyboardVisible(true);
  }, []);

  const handleInputBlur = useCallback(() => {
    setKeyboardVisible(false);
  }, []);

  // 設定ボタン押下
  const handleSettingsPress = useCallback(() => {
    // TODO: 設定画面へ遷移
  }, []);

  // 現在のウィンドウ一覧
  const windows = useMemo(() => {
    return currentSession?.windows ?? [];
  }, [currentSession]);

  // エラー表示
  const error = sshError ?? tmuxError;

  // 接続中
  if (isConnecting) {
    return (
      <>
        <Stack.Screen
          options={{
            headerShown: false,
          }}
        />
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={styles.statusText}>接続中...</Text>
        </View>
      </>
    );
  }

  // エラー
  if (error) {
    return (
      <>
        <Stack.Screen
          options={{
            headerShown: false,
          }}
        />
        <View style={styles.centerContainer}>
          <Text style={styles.errorText}>接続エラー</Text>
          <Text style={styles.errorDetail}>{error}</Text>
        </View>
      </>
    );
  }

  // tmuxセッションがない
  if (isConnected && !tmuxLoading && sessions.length === 0) {
    return (
      <>
        <Stack.Screen
          options={{
            headerShown: false,
          }}
        />
        <View style={styles.centerContainer}>
          <Text style={styles.emptyText}>tmuxセッションがありません</Text>
          <Text style={styles.emptyHint}>
            サーバーで `tmux new -s session` を実行してください
          </Text>
        </View>
      </>
    );
  }

  // ローディング
  if (tmuxLoading) {
    return (
      <>
        <Stack.Screen
          options={{
            headerShown: false,
          }}
        />
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={styles.statusText}>セッション読み込み中...</Text>
        </View>
      </>
    );
  }

  return (
    <>
      <Stack.Screen
        options={{
          headerShown: false,
        }}
      />
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 0}
      >
        {/* ヘッダー（セッション名 + ウィンドウタブ + レイテンシ） */}
        <TerminalHeader
          sessionName={selectedSession}
          windows={windows}
          selectedWindow={selectedWindow}
          onSelectWindow={handleWindowSelect}
          latency={latency}
          onSettingsPress={handleSettingsPress}
        />

        {/* ターミナル表示 */}
        <View style={styles.terminalContainer}>
          <TerminalView lines={lines} />
        </View>

        {/* フッター: bg-[#14151a] border-t border-white/10 */}
        {!keyboardVisible && (
          <View style={styles.footer}>
            {/* 特殊キー */}
            <SpecialKeys
              onSendKeys={handleSendKeys}
              onSendSpecialKey={handleSendSpecialKey}
              onSendCtrl={handleSendCtrl}
              disabled={!isConnected || selectedPane === null}
            />

            {/* テキスト入力 */}
            <TerminalInput
              onSendKeys={handleSendKeys}
              onSendSpecialKey={handleSendSpecialKey}
              onFocus={handleInputFocus}
              onBlur={handleInputBlur}
              disabled={!isConnected || selectedPane === null}
            />

            {/* 下部スペーサー: h-4 bg-[#14151a] */}
            <View style={styles.footerSpacer} />
          </View>
        )}

        {/* キーボード表示時はテキスト入力のみ表示 */}
        {keyboardVisible && (
          <TerminalInput
            onSendKeys={handleSendKeys}
            onSendSpecialKey={handleSendSpecialKey}
            onFocus={handleInputFocus}
            onBlur={handleInputBlur}
            disabled={!isConnected || selectedPane === null}
          />
        )}
      </KeyboardAvoidingView>

      {/* 再接続ダイアログ */}
      {connection && (
        <ReconnectDialog
          visible={reconnectVisible}
          connection={connection}
          connectionState={connectionState}
          onReconnect={reconnect}
          onCancel={cancelReconnect}
          onDismiss={hideReconnect}
          onRetry={retry}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centerContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
    padding: spacing.lg,
  },
  terminalContainer: {
    flex: 1,
  },
  // フッター: bg-[#14151a] border-t border-white/10
  footer: {
    backgroundColor: colors.footerBg,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255, 255, 255, 0.1)',
  },
  // 下部スペーサー: h-4
  footerSpacer: {
    height: 16,  // h-4
    backgroundColor: colors.footerBg,
  },
  statusText: {
    fontSize: fontSize.lg,
    color: colors.text,
    marginTop: spacing.md,
  },
  errorText: {
    fontSize: fontSize.xl,
    color: colors.error,
    fontWeight: '600',
    marginBottom: spacing.sm,
  },
  errorDetail: {
    fontSize: fontSize.md,
    color: colors.textSecondary,
    textAlign: 'center',
  },
  emptyText: {
    fontSize: fontSize.xl,
    color: colors.text,
    fontWeight: '600',
    marginBottom: spacing.sm,
  },
  emptyHint: {
    fontSize: fontSize.md,
    color: colors.textSecondary,
    textAlign: 'center',
    fontFamily: 'monospace',
  },
});
