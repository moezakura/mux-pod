/**
 * SpecialKeys
 *
 * 特殊キー入力バーコンポーネント。
 * HTMLデザイン (terminal_main_view_1.html) に完全準拠。
 */
import { memo, useCallback, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '@/theme';

export interface SpecialKeysProps {
  /** キーを送信する（リテラルモード） */
  onSendKeys: (keys: string) => void;
  /** 特殊キーを送信する（非リテラルモード） */
  onSendSpecialKey: (key: string) => void;
  /** Ctrl+キーを送信する */
  onSendCtrl: (key: string) => void;
  /** 無効化 */
  disabled?: boolean;
}

/**
 * キーボタン
 * HTMLデザイン準拠:
 * - h-8 min-w-[3rem] flex-1 rounded
 * - bg-[#2A2B35] text-white/90 font-mono text-[10px] font-bold
 * - border-b border-black
 * - active:bg-primary active:text-black active:translate-y-[1px]
 * - CTRL特別: text-primary bg-primary/10 border border-primary/30
 */
const KeyButton = memo(function KeyButton({
  label,
  onPress,
  disabled,
  active,
  isCtrl,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  active?: boolean;
  isCtrl?: boolean;
}) {
  return (
    <Pressable
      style={({ pressed }) => [
        styles.keyButton,
        isCtrl && !active && styles.keyButtonCtrl,
        active && styles.keyButtonActive,
        pressed && !active && styles.keyButtonPressed,
        disabled && styles.keyButtonDisabled,
      ]}
      onPress={onPress}
      disabled={disabled}
    >
      {/* CTRLキーにはドットインジケーターを表示 */}
      {isCtrl && !active && <View style={styles.ctrlDot} />}
      <Text
        style={[
          styles.keyLabel,
          isCtrl && !active && styles.keyLabelCtrl,
          active && styles.keyLabelActive,
          disabled && styles.keyLabelDisabled,
        ]}
      >
        {label}
      </Text>
    </Pressable>
  );
});

/**
 * SpecialKeys
 */
export const SpecialKeys = memo(function SpecialKeys({
  onSendKeys,
  onSendSpecialKey,
  onSendCtrl,
  disabled = false,
}: SpecialKeysProps) {
  const [ctrlMode, setCtrlMode] = useState(false);
  const [altMode, setAltMode] = useState(false);

  // ESC
  const handleEsc = useCallback(() => {
    onSendSpecialKey('Escape');
  }, [onSendSpecialKey]);

  // TAB
  const handleTab = useCallback(() => {
    onSendSpecialKey('Tab');
  }, [onSendSpecialKey]);

  // CTRL toggle
  const toggleCtrl = useCallback(() => {
    setCtrlMode((prev) => !prev);
    setAltMode(false);
  }, []);

  // ALT toggle
  const toggleAlt = useCallback(() => {
    setAltMode((prev) => !prev);
    setCtrlMode(false);
  }, []);

  // リテラルキー
  const handleLiteral = useCallback(
    (key: string) => {
      if (ctrlMode) {
        onSendCtrl(key);
        setCtrlMode(false);
      } else {
        onSendKeys(key);
      }
    },
    [ctrlMode, onSendKeys, onSendCtrl]
  );

  return (
    <View style={styles.container}>
      <View style={styles.row}>
        <KeyButton label="ESC" onPress={handleEsc} disabled={disabled} />
        <KeyButton label="TAB" onPress={handleTab} disabled={disabled} />
        <KeyButton
          label="CTRL"
          onPress={toggleCtrl}
          disabled={disabled}
          active={ctrlMode}
          isCtrl
        />
        <KeyButton
          label="ALT"
          onPress={toggleAlt}
          disabled={disabled}
          active={altMode}
        />
        <KeyButton
          label="/"
          onPress={() => handleLiteral('/')}
          disabled={disabled}
        />
        <KeyButton
          label="-"
          onPress={() => handleLiteral('-')}
          disabled={disabled}
        />
        <KeyButton
          label="|"
          onPress={() => handleLiteral('|')}
          disabled={disabled}
        />
      </View>
    </View>
  );
});

/**
 * ArrowKeys - 矢印キーコンポーネント
 * HTMLデザイン準拠:
 * - 左右キー: h-9 w-9 rounded bg-[#2A2B35] border border-white/5
 * - 上下キー: h-[17px] w-9
 */
export const ArrowKeys = memo(function ArrowKeys({
  onSendSpecialKey,
  disabled = false,
}: {
  onSendSpecialKey: (key: string) => void;
  disabled?: boolean;
}) {
  const handleUp = useCallback(() => {
    onSendSpecialKey('Up');
  }, [onSendSpecialKey]);

  const handleDown = useCallback(() => {
    onSendSpecialKey('Down');
  }, [onSendSpecialKey]);

  const handleLeft = useCallback(() => {
    onSendSpecialKey('Left');
  }, [onSendSpecialKey]);

  const handleRight = useCallback(() => {
    onSendSpecialKey('Right');
  }, [onSendSpecialKey]);

  return (
    <View style={styles.arrowContainer}>
      {/* Left */}
      <Pressable
        style={({ pressed }) => [
          styles.arrowButton,
          pressed && styles.arrowButtonPressed,
          disabled && styles.arrowButtonDisabled,
        ]}
        onPress={handleLeft}
        disabled={disabled}
      >
        <MaterialIcons
          name="arrow-left"
          size={16}
          color={colors.text}
        />
      </Pressable>

      {/* Up / Down */}
      <View style={styles.arrowVertical}>
        <Pressable
          style={({ pressed }) => [
            styles.arrowButtonSmall,
            pressed && styles.arrowButtonPressed,
            disabled && styles.arrowButtonDisabled,
          ]}
          onPress={handleUp}
          disabled={disabled}
        >
          <MaterialIcons
            name="arrow-drop-up"
            size={14}
            color={colors.text}
          />
        </Pressable>
        <Pressable
          style={({ pressed }) => [
            styles.arrowButtonSmall,
            pressed && styles.arrowButtonPressed,
            disabled && styles.arrowButtonDisabled,
          ]}
          onPress={handleDown}
          disabled={disabled}
        >
          <MaterialIcons
            name="arrow-drop-down"
            size={14}
            color={colors.text}
          />
        </Pressable>
      </View>

      {/* Right */}
      <Pressable
        style={({ pressed }) => [
          styles.arrowButton,
          pressed && styles.arrowButtonPressed,
          disabled && styles.arrowButtonDisabled,
        ]}
        onPress={handleRight}
        disabled={disabled}
      >
        <MaterialIcons
          name="arrow-right"
          size={16}
          color={colors.text}
        />
      </Pressable>
    </View>
  );
});

/**
 * スタイル定義 - HTMLデザイン準拠
 */
const styles = StyleSheet.create({
  // 特殊キー行コンテナ: bg-[#1E1F27] px-1 py-1 gap-1
  container: {
    backgroundColor: colors.surface,  // #1E1F27
    paddingVertical: 4,   // py-1
    paddingHorizontal: 4, // px-1
  },
  row: {
    flexDirection: 'row',
    gap: 4,  // gap-1
  },
  // 通常キーボタン: h-8 min-w-[3rem] flex-1 rounded bg-[#2A2B35] border-b border-black
  keyButton: {
    flex: 1,
    height: 32,      // h-8
    minWidth: 48,    // min-w-[3rem]
    backgroundColor: '#2A2B35',  // bg-[#2A2B35]
    borderRadius: borderRadius.sm,  // rounded
    justifyContent: 'center',
    alignItems: 'center',
    flexDirection: 'row',
    gap: 4,
    borderBottomWidth: 1,
    borderBottomColor: '#000000',  // border-black
  },
  // CTRLキー特別スタイル: bg-primary/10 border border-primary/30
  keyButtonCtrl: {
    backgroundColor: 'rgba(0, 192, 209, 0.1)',  // bg-primary/10
    borderWidth: 1,
    borderColor: 'rgba(0, 192, 209, 0.3)',  // border-primary/30
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(0, 192, 209, 0.3)',
  },
  // アクティブ状態: active:bg-primary active:border-none
  keyButtonActive: {
    backgroundColor: colors.primary,
    borderBottomWidth: 0,
  },
  // 押下状態: active:bg-primary active:translate-y-[1px]
  keyButtonPressed: {
    backgroundColor: colors.primary,
    borderBottomWidth: 0,
    transform: [{ translateY: 1 }],
  },
  keyButtonDisabled: {
    opacity: 0.5,
  },
  // CTRL用ドットインジケーター
  ctrlDot: {
    width: 4,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.primary,
  },
  // キーラベル: text-white/90 font-mono text-[10px] font-bold tracking-wider
  keyLabel: {
    color: 'rgba(255, 255, 255, 0.9)',  // text-white/90
    fontSize: 10,        // text-[10px]
    fontWeight: '700',   // font-bold
    fontFamily: 'monospace',  // font-mono
    letterSpacing: 0.5,  // tracking-wider
  },
  // CTRLラベル: text-primary
  keyLabelCtrl: {
    color: colors.primary,
  },
  // アクティブラベル: text-black
  keyLabelActive: {
    color: '#000000',  // text-black
  },
  keyLabelDisabled: {
    color: colors.textMuted,
  },

  // 矢印キーコンテナ
  arrowContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,  // gap-0.5
  },
  // 左右矢印: h-9 w-9 rounded bg-[#2A2B35] border border-white/5
  arrowButton: {
    width: 36,   // w-9
    height: 36,  // h-9
    backgroundColor: '#2A2B35',
    borderRadius: borderRadius.sm,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.05)',  // border-white/5
    justifyContent: 'center',
    alignItems: 'center',
  },
  arrowButtonPressed: {
    backgroundColor: colors.primary,
  },
  arrowButtonDisabled: {
    opacity: 0.5,
  },
  // 上下矢印コンテナ
  arrowVertical: {
    gap: 2,  // gap-0.5
  },
  // 上下矢印: h-[17px] w-9
  arrowButtonSmall: {
    width: 36,   // w-9
    height: 17,  // h-[17px]
    backgroundColor: '#2A2B35',
    borderRadius: borderRadius.sm,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.05)',
    justifyContent: 'center',
    alignItems: 'center',
  },
});
