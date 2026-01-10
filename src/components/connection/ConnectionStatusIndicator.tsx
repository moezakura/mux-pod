/**
 * ConnectionStatusIndicator
 *
 * 接続状態を視覚的に表示するインジケーターコンポーネント。
 */
import React, { useEffect, useRef } from 'react';
import {
  View,
  Text,
  Pressable,
  Animated,
  Easing,
  StyleSheet,
} from 'react-native';
import type { ConnectionState, ConnectionStatus } from '@/types/connection';

/**
 * インジケーターサイズ
 */
export type IndicatorSize = 'sm' | 'md' | 'lg';

/**
 * Props
 */
export interface ConnectionStatusIndicatorProps {
  /** 接続状態 */
  state: ConnectionState;
  /** サイズ */
  size?: IndicatorSize;
  /** タップ時のコールバック */
  onPress?: () => void;
  /** 詳細情報を表示するか */
  showDetails?: boolean;
  /** アニメーション有効 */
  animated?: boolean;
}

/**
 * 状態ごとの表示仕様
 */
const STATUS_DISPLAY: Record<
  ConnectionStatus,
  { color: string; label: string; animate: boolean }
> = {
  connected: {
    color: '#22c55e',
    label: '接続中',
    animate: false,
  },
  connecting: {
    color: '#eab308',
    label: '接続中...',
    animate: true,
  },
  reconnecting: {
    color: '#eab308',
    label: '再接続中...',
    animate: true,
  },
  disconnected: {
    color: '#ef4444',
    label: '切断',
    animate: false,
  },
  error: {
    color: '#ef4444',
    label: 'エラー',
    animate: false,
  },
};

/**
 * サイズごとの寸法
 */
const SIZE_SPECS: Record<IndicatorSize, { iconSize: number; fontSize: number }> = {
  sm: { iconSize: 12, fontSize: 10 },
  md: { iconSize: 16, fontSize: 12 },
  lg: { iconSize: 20, fontSize: 14 },
};

/**
 * ConnectionStatusIndicator
 */
export function ConnectionStatusIndicator({
  state,
  size = 'md',
  onPress,
  showDetails = false,
  animated = true,
}: ConnectionStatusIndicatorProps): React.JSX.Element {
  const { status, reconnectAttempt } = state;
  const display = STATUS_DISPLAY[status];
  const sizeSpec = SIZE_SPECS[size];

  // アニメーション用
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const rotateAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (!animated || !display.animate) {
      pulseAnim.setValue(1);
      rotateAnim.setValue(0);
      return;
    }

    if (status === 'reconnecting') {
      // 回転アニメーション
      const rotation = Animated.loop(
        Animated.timing(rotateAnim, {
          toValue: 1,
          duration: 1000,
          easing: Easing.linear,
          useNativeDriver: true,
        })
      );
      rotation.start();
      return () => rotation.stop();
    } else if (status === 'connecting') {
      // パルスアニメーション
      const pulse = Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, {
            toValue: 0.5,
            duration: 500,
            useNativeDriver: true,
          }),
          Animated.timing(pulseAnim, {
            toValue: 1,
            duration: 500,
            useNativeDriver: true,
          }),
        ])
      );
      pulse.start();
      return () => pulse.stop();
    }
  }, [status, animated, display.animate, pulseAnim, rotateAnim]);

  const rotate = rotateAnim.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg'],
  });

  // ラベルテキスト
  let label = display.label;
  if (status === 'reconnecting' && reconnectAttempt) {
    label = `再接続中 (${reconnectAttempt.attemptNumber}/${reconnectAttempt.maxAttempts})`;
  }

  const indicatorStyle = [
    styles.indicator,
    {
      width: sizeSpec.iconSize,
      height: sizeSpec.iconSize,
      borderRadius: sizeSpec.iconSize / 2,
      backgroundColor: display.color,
    },
  ];

  const animatedStyle =
    status === 'reconnecting'
      ? { transform: [{ rotate }] }
      : status === 'connecting'
        ? { opacity: pulseAnim }
        : {};

  const content = (
    <View style={styles.container}>
      <Animated.View
        testID="status-indicator"
        style={[indicatorStyle, animatedStyle]}
      />
      {showDetails && (
        <Text
          style={[styles.label, { fontSize: sizeSpec.fontSize }]}
          testID="status-label"
        >
          {label}
        </Text>
      )}
    </View>
  );

  if (onPress) {
    return (
      <Pressable testID="status-touchable" onPress={onPress}>
        {content}
      </Pressable>
    );
  }

  return content;
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  indicator: {
    // 基本スタイルはpropsで上書き
  },
  label: {
    color: '#9ca3af',
  },
});
