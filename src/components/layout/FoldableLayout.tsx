/**
 * FoldableLayout
 *
 * 折りたたみデバイス/大画面対応の2ペインレイアウト。
 * 大画面時: 左にサイドバー、右にメインコンテンツ
 * コンパクト時: メインコンテンツのみ表示
 */
import { View, StyleSheet } from 'react-native';
import { useLayout } from '@/hooks/useLayout';
import { Sidebar, type SidebarProps } from './Sidebar';
import { colors } from '@/theme';

export interface FoldableLayoutProps extends Omit<SidebarProps, 'onConnectionPress'> {
  /** メインコンテンツ */
  children: React.ReactNode;
  /** 接続タップ時（大画面では同じ画面内で切り替え） */
  onConnectionPress?: SidebarProps['onConnectionPress'];
}

export function FoldableLayout({
  children,
  connections,
  connectionStates,
  activeConnectionId,
  onConnectionPress,
  sessions,
  selectedSession,
  selectedWindow,
  selectedPane,
  onSessionSelect,
  onWindowSelect,
  onPaneSelect,
  onAddConnection,
  onSettingsPress,
}: FoldableLayoutProps) {
  const { isExpanded } = useLayout();

  // コンパクトモード: メインコンテンツのみ
  if (!isExpanded) {
    return <View style={styles.container}>{children}</View>;
  }

  // 大画面モード: サイドバー + メインコンテンツ
  return (
    <View style={styles.container}>
      <Sidebar
        connections={connections}
        connectionStates={connectionStates}
        activeConnectionId={activeConnectionId}
        onConnectionPress={onConnectionPress}
        sessions={sessions}
        selectedSession={selectedSession}
        selectedWindow={selectedWindow}
        selectedPane={selectedPane}
        onSessionSelect={onSessionSelect}
        onWindowSelect={onWindowSelect}
        onPaneSelect={onPaneSelect}
        onAddConnection={onAddConnection}
        onSettingsPress={onSettingsPress}
      />
      <View style={styles.mainContent}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'row',
    backgroundColor: colors.background,
  },
  mainContent: {
    flex: 1,
  },
});
