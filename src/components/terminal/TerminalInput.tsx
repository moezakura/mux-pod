/**
 * TerminalInput
 *
 * テキスト入力バーコンポーネント。
 * HTMLデザイン (terminal_main_view_1.html) に完全準拠。
 */
import { memo, useCallback, useRef, useState } from 'react';
import {
  View,
  TextInput,
  StyleSheet,
  Pressable,
  Text,
  type NativeSyntheticEvent,
  type TextInputKeyPressEventData,
  type TextInputSubmitEditingEventData,
} from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '@/theme';
import { ArrowKeys } from './SpecialKeys';

export interface TerminalInputProps {
  /** キーを送信する */
  onSendKeys: (keys: string) => void;
  /** 特殊キーを送信する */
  onSendSpecialKey: (key: string) => void;
  /** フォーカス時コールバック */
  onFocus?: () => void;
  /** ブラー時コールバック */
  onBlur?: () => void;
  /** 無効化 */
  disabled?: boolean;
  /** プレースホルダー */
  placeholder?: string;
}

/**
 * TerminalInput
 */
export const TerminalInput = memo(function TerminalInput({
  onSendKeys,
  onSendSpecialKey,
  onFocus,
  onBlur,
  disabled = false,
  placeholder = 'Input...',
}: TerminalInputProps) {
  const inputRef = useRef<TextInput>(null);
  const [inputValue, setInputValue] = useState('');
  const [isFocused, setIsFocused] = useState(false);

  // テキスト変更時
  const handleChangeText = useCallback((text: string) => {
    setInputValue(text);
  }, []);

  // キープレス処理
  const handleKeyPress = useCallback(
    (e: NativeSyntheticEvent<TextInputKeyPressEventData>) => {
      const { key } = e.nativeEvent;

      switch (key) {
        case 'Backspace':
          onSendSpecialKey('BSpace');
          return;
        case 'Enter':
          return;
        case 'Tab':
          e.preventDefault?.();
          onSendSpecialKey('Tab');
          return;
        case 'Escape':
          onSendSpecialKey('Escape');
          return;
        case 'ArrowUp':
          onSendSpecialKey('Up');
          return;
        case 'ArrowDown':
          onSendSpecialKey('Down');
          return;
        case 'ArrowLeft':
          onSendSpecialKey('Left');
          return;
        case 'ArrowRight':
          onSendSpecialKey('Right');
          return;
      }
    },
    [onSendSpecialKey]
  );

  // Enter送信時
  const handleSubmitEditing = useCallback(
    (_e: NativeSyntheticEvent<TextInputSubmitEditingEventData>) => {
      if (inputValue.length > 0) {
        onSendKeys(inputValue);
      }
      onSendSpecialKey('Enter');
      setInputValue('');
    },
    [inputValue, onSendKeys, onSendSpecialKey]
  );

  // cmdボタン押下
  const handleCmdPress = useCallback(() => {
    if (inputValue.length > 0) {
      onSendKeys(inputValue);
      onSendSpecialKey('Enter');
      setInputValue('');
    } else {
      onSendSpecialKey('Enter');
    }
  }, [inputValue, onSendKeys, onSendSpecialKey]);

  // +ボタン押下（メニュー表示など）
  const handlePlusPress = useCallback(() => {
    // TODO: コマンドメニュー表示
  }, []);

  // フォーカス処理
  const handleFocus = useCallback(() => {
    setIsFocused(true);
    onFocus?.();
  }, [onFocus]);

  const handleBlur = useCallback(() => {
    setIsFocused(false);
    onBlur?.();
  }, [onBlur]);

  // インプットにフォーカス
  const focusInput = useCallback(() => {
    inputRef.current?.focus();
  }, []);

  return (
    <View style={styles.container}>
      {/* 矢印キー */}
      <ArrowKeys onSendSpecialKey={onSendSpecialKey} disabled={disabled} />

      {/* 入力フィールド */}
      <Pressable
        style={[
          styles.inputWrapper,
          isFocused && styles.inputWrapperFocused,
          disabled && styles.inputWrapperDisabled,
        ]}
        onPress={focusInput}
      >
        <View style={styles.inputLeft}>
          <MaterialIcons
            name="keyboard"
            size={16}
            color="rgba(0, 192, 209, 0.7)"
          />
          <TextInput
            ref={inputRef}
            style={styles.input}
            value={inputValue}
            onChangeText={handleChangeText}
            onKeyPress={handleKeyPress}
            onSubmitEditing={handleSubmitEditing}
            onFocus={handleFocus}
            onBlur={handleBlur}
            placeholder={placeholder}
            placeholderTextColor="rgba(0, 192, 209, 0.5)"
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="off"
            editable={!disabled}
            blurOnSubmit={false}
            returnKeyType="send"
          />
        </View>
        <Pressable
          style={({ pressed }) => [
            styles.cmdBadge,
            pressed && styles.cmdBadgePressed,
          ]}
          onPress={handleCmdPress}
          disabled={disabled}
        >
          <Text style={styles.cmdBadgeText}>cmd</Text>
        </Pressable>
      </Pressable>

      {/* +ボタン */}
      <Pressable
        style={({ pressed }) => [
          styles.plusButton,
          pressed && styles.plusButtonPressed,
          disabled && styles.buttonDisabled,
        ]}
        onPress={handlePlusPress}
        disabled={disabled}
      >
        <MaterialIcons
          name="add"
          size={18}
          color={colors.text}
        />
      </Pressable>
    </View>
  );
});

/**
 * スタイル定義 - HTMLデザイン準拠
 * 入力行: flex items-center gap-1.5 px-1 pb-2 pt-1
 */
const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 4,   // px-1
    paddingTop: 4,          // pt-1
    paddingBottom: 8,       // pb-2
    gap: 6,                 // gap-1.5
    // 背景は親コンポーネントで設定
  },
  // 入力バー: flex-1 h-9 rounded bg-primary/5 border border-primary/20
  inputWrapper: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: 'rgba(0, 192, 209, 0.05)',  // bg-primary/5
    borderRadius: borderRadius.sm,
    borderWidth: 1,
    borderColor: 'rgba(0, 192, 209, 0.2)',  // border-primary/20
    paddingHorizontal: 12,  // px-3
    height: 36,  // h-9
  },
  inputWrapperFocused: {
    borderColor: 'rgba(0, 192, 209, 0.5)',
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
  },
  inputWrapperDisabled: {
    opacity: 0.5,
  },
  inputLeft: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,  // gap-2
  },
  input: {
    flex: 1,
    color: colors.text,
    fontSize: 12,  // text-xs
    fontFamily: 'monospace',
    padding: 0,
  },
  // cmdバッジ: text-[10px] bg-primary/10 text-primary px-1.5 rounded border border-primary/10
  cmdBadge: {
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    borderWidth: 1,
    borderColor: 'rgba(0, 192, 209, 0.1)',
    borderRadius: borderRadius.sm,
    paddingHorizontal: 6,  // px-1.5
    paddingVertical: 2,
  },
  cmdBadgePressed: {
    backgroundColor: 'rgba(0, 192, 209, 0.2)',
  },
  cmdBadgeText: {
    color: colors.primary,
    fontSize: 10,  // text-[10px]
    fontFamily: 'monospace',
  },
  // +ボタン: h-9 w-9 rounded bg-[#2A2B35] border border-white/5
  plusButton: {
    width: 36,   // w-9
    height: 36,  // h-9
    backgroundColor: '#2A2B35',
    borderRadius: borderRadius.sm,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.05)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  plusButtonPressed: {
    backgroundColor: colors.text,  // active:bg-white
  },
  buttonDisabled: {
    opacity: 0.5,
  },
});
