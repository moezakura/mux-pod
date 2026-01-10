/**
 * TerminalHeader
 *
 * ターミナル画面のヘッダーコンポーネント。
 * HTMLデザイン (terminal_main_view_1.html) に完全準拠。
 */
import { memo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { MaterialIcons, MaterialCommunityIcons } from '@expo/vector-icons';
import type { TmuxWindow } from '@/types/tmux';
import type { ConnectionState } from '@/types/connection';
import { colors, spacing, fontSize, borderRadius, header } from '@/theme';
import { ConnectionStatusIndicator } from '@/components/connection';

export interface TerminalHeaderProps {
  /** セッション名 */
  sessionName: string | null;
  /** ウィンドウ一覧 */
  windows: TmuxWindow[];
  /** 選択中のウィンドウインデックス */
  selectedWindow: number | null;
  /** ウィンドウ選択時のコールバック */
  onSelectWindow: (index: number) => void;
  /** レイテンシ（ミリ秒） */
  latency?: number;
  /** 接続状態 */
  connectionState?: ConnectionState;
  /** 接続状態インジケーター押下時 */
  onStatusPress?: () => void;
  /** 設定ボタン押下時 */
  onSettingsPress?: () => void;
}

/**
 * TerminalHeader
 */
export const TerminalHeader = memo(function TerminalHeader({
  sessionName,
  windows,
  selectedWindow,
  onSelectWindow,
  latency,
  connectionState,
  onStatusPress,
  onSettingsPress,
}: TerminalHeaderProps) {
  return (
    <View style={styles.container}>
      {/* 左側: セッション + ウィンドウタブ */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.tabsContainer}
        style={styles.tabsScroll}
      >
        {/* dns アイコン */}
        <MaterialIcons
          name="dns"
          size={14}
          color="rgba(0, 192, 209, 0.8)"
          style={styles.dnsIcon}
        />

        {/* セッション名 */}
        <Pressable style={styles.sessionButton}>
          <Text style={styles.sessionName}>{sessionName ?? 'session'}</Text>
        </Pressable>

        {/* 区切り */}
        <Text style={styles.separator}>/</Text>

        {/* ウィンドウタブ */}
        {windows.map((window, index) => {
          const isActive = window.index === selectedWindow;
          return (
            <View key={window.index} style={styles.windowTabWrapper}>
              {index > 0 && <Text style={styles.separator}>/</Text>}
              <Pressable
                style={[
                  styles.windowTab,
                  isActive && styles.windowTabActive,
                ]}
                onPress={() => onSelectWindow(window.index)}
              >
                {isActive && (
                  <MaterialIcons
                    name="article"
                    size={12}
                    color={colors.primary}
                    style={styles.windowIcon}
                  />
                )}
                <Text
                  style={[
                    styles.windowName,
                    isActive && styles.windowNameActive,
                    !isActive && styles.windowNameInactive,
                  ]}
                  numberOfLines={1}
                >
                  {window.name}
                </Text>
              </Pressable>
            </View>
          );
        })}
      </ScrollView>

      {/* 右側: 接続状態 + レイテンシ + 設定 */}
      <View style={styles.rightSection}>
        {connectionState && (
          <ConnectionStatusIndicator
            state={connectionState}
            size="sm"
            onPress={onStatusPress}
          />
        )}
        {latency !== undefined && (
          <View style={styles.latency}>
            <MaterialCommunityIcons
              name="lightning-bolt"
              size={10}
              color="rgba(0, 192, 209, 0.8)"
            />
            <Text style={styles.latencyText}>{latency}ms</Text>
          </View>
        )}
        <Pressable
          style={({ pressed }) => [
            styles.settingsButton,
            pressed && styles.settingsButtonPressed,
          ]}
          onPress={onSettingsPress}
        >
          <MaterialIcons
            name="settings"
            size={16}
            color="rgba(255, 255, 255, 0.6)"
          />
        </Pressable>
      </View>
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(30, 31, 39, 0.9)',
    height: header.height,
    paddingHorizontal: header.paddingHorizontal,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255, 255, 255, 0.05)',
  },
  tabsScroll: {
    flex: 1,
  },
  tabsContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  dnsIcon: {
    marginRight: spacing.sm,
  },
  sessionButton: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  sessionName: {
    fontSize: fontSize.sm,
    fontWeight: '700',
    color: colors.primary,
  },
  separator: {
    fontSize: fontSize.xs,
    color: 'rgba(255, 255, 255, 0.2)',
    marginHorizontal: spacing.xs,
    fontWeight: '300',
  },
  windowTabWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  windowTab: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
  },
  windowTabActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.05)',
  },
  windowIcon: {
    marginRight: spacing.xs,
  },
  windowName: {
    fontSize: 11,
    fontFamily: 'monospace',
  },
  windowNameActive: {
    color: colors.text,
    fontWeight: '700',
  },
  windowNameInactive: {
    color: 'rgba(255, 255, 255, 0.7)',
    opacity: 0.5,
  },
  rightSection: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingLeft: spacing.sm,
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(255, 255, 255, 0.1)',
    marginLeft: 'auto',
    backgroundColor: 'rgba(30, 31, 39, 0.9)',
    gap: spacing.sm,
  },
  latency: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  latencyText: {
    fontSize: fontSize.xxs,
    fontFamily: 'monospace',
    color: 'rgba(0, 192, 209, 0.8)',
  },
  settingsButton: {
    padding: spacing.xs,
    borderRadius: borderRadius.sm,
  },
  settingsButtonPressed: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
  },
});
