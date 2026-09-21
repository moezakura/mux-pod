import 'package:flutter/material.dart';

import '../services/custom_keys/custom_key_button.dart';
import 'custom_key_button_widget.dart';
import 'special_keys_bar_buttons.dart';
import 'special_keys_bar_tool_buttons.dart';
import 'special_keys_direct_input_engine.dart';
import 'special_keys_modifier_state.dart';

/// トークン→ボタンWidget解決（18種スイッチ・`ck:`カスタム解決・幅計算）と
/// モード依存可視性ルールの所有者。
///
/// 状態を持たず、合成ルート State が widget の最新値を注入して
/// 毎ビルドで生成するコンフィグレーションオブジェクトとして使う。
class SpecialKeysTokenView {
  SpecialKeysTokenView({
    required this.modifiers,
    required this.callbacks,
    required this.customButtons,
    required this.directInputEnabled,
    required this.sendSpecialKey,
    required this.sendLiteralKey,
    this.onInputTap,
    this.onDirectInputToggle,
    this.onImagePickRequested,
    this.onCustomButtonEdit,
  });

  /// ソフトウェア修飾子状態（modifierトークンの押下状態・カスタムボタンの
  /// 修飾子リセット用）。
  final SpecialKeysModifierState modifiers;

  /// コールバック値オブジェクト（送信・haptic 用。状態を含まない）。
  final SpecialKeysBarCallbacks callbacks;

  final List<CustomKeyButton> customButtons;
  final bool directInputEnabled;

  /// 特殊キー送信オーケスト（修飾子消費を含む。合成ルートが提供）。
  final void Function(String tmuxKey) sendSpecialKey;

  /// リテラルキー送信オーケスト（修飾子消費を含む。合成ルートが提供）。
  final void Function(String key) sendLiteralKey;

  final VoidCallback? onInputTap;
  final VoidCallback? onDirectInputToggle;
  final VoidCallback? onImagePickRequested;
  final void Function(CustomKeyButton)? onCustomButtonEdit;

  /// モード依存のスキップを適用した可視トークン列。
  /// 純粋（単体テスト可能）。
  static List<String> visibleOf(
    List<String> tokens, {
    required bool directInputEnabled,
    required bool hasImage,
  }) => tokens
      .where(
        (t) => shouldRender(
          t,
          directInputEnabled: directInputEnabled,
          hasImage: hasImage,
        ),
      )
      .toList();

  /// モード依存のトークンスキップ（input / num1..num4 / image）。
  /// 純粋（単体テスト可能）。
  static bool shouldRender(
    String token, {
    required bool directInputEnabled,
    required bool hasImage,
  }) {
    if (token == 'input') return !directInputEnabled;
    if (CustomKeyRows.directInputExtras.contains(token)) {
      return directInputEnabled;
    }
    if (token == 'image') return hasImage;
    return true;
  }

  /// 標準トークン・カスタムトークンを問わず単一トークンを描画する。
  /// [height] はカスタムボタンの高さ（行0/行1=32、行2=36）。
  Widget build(BuildContext context, String token, {required double height}) {
    switch (token) {
      case 'esc':
        return SpecialKeyButton(
          label: 'ESC',
          onTap: () => sendSpecialKey('Escape'),
          hapticFeedback: callbacks.hapticFeedback,
          width: 40,
        );
      case 'tab':
        return SpecialKeyButton(
          label: 'TAB',
          onTap: () => sendSpecialKey('Tab'),
          hapticFeedback: callbacks.hapticFeedback,
          width: 40,
        );
      case 'ctrl':
        return ModifierButton(
          label: 'CTRL',
          isPressed: modifiers.ctrl,
          onPressed: modifiers.toggleCtrl,
          hapticFeedback: callbacks.hapticFeedback,
          width: 44,
        );
      case 'alt':
        return ModifierButton(
          label: 'ALT',
          isPressed: modifiers.alt,
          onPressed: modifiers.toggleAlt,
          hapticFeedback: callbacks.hapticFeedback,
          width: 44,
        );
      case 'shift':
        return ModifierButton(
          label: 'SHIFT',
          isPressed: modifiers.shift,
          onPressed: modifiers.toggleShift,
          hapticFeedback: callbacks.hapticFeedback,
          width: 48,
        );
      case 'enter':
        return EnterKeyButton(
          onTap: () => sendSpecialKey('Enter'),
          hapticFeedback: callbacks.hapticFeedback,
          width: 56,
        );
      case 'senter':
        return ShiftEnterKeyButton(
          onTap: () => sendSpecialKey('S-Enter'),
          hapticFeedback: callbacks.hapticFeedback,
          width: 56,
        );
      case 'slash':
        return LiteralKeyButton(
          label: '/',
          onTap: () => sendLiteralKey('/'),
          hapticFeedback: callbacks.hapticFeedback,
          width: 32,
        );
      case 'dash':
        return LiteralKeyButton(
          label: '-',
          onTap: () => sendLiteralKey('-'),
          hapticFeedback: callbacks.hapticFeedback,
          width: 32,
        );
      // Without this there is no way to erase anything typed from this bar:
      // its literal keys go straight into the pane, and the phone keyboard is
      // only reachable in Direct Input mode.
      case 'bspace':
        return NavigationKeyButton(
          label: '\u232b',
          onTap: () => sendSpecialKey('BSpace'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'pgup':
        return NavigationKeyButton(
          label: 'PgUp',
          onTap: () => sendSpecialKey('PPage'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'pgdn':
        return NavigationKeyButton(
          label: 'PgDn',
          onTap: () => sendSpecialKey('NPage'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'left':
        return ArrowKeyButton(
          icon: Icons.arrow_left,
          onTap: () => sendSpecialKey('Left'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'up':
        return ArrowKeyButton(
          icon: Icons.arrow_drop_up,
          onTap: () => sendSpecialKey('Up'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'down':
        return ArrowKeyButton(
          icon: Icons.arrow_drop_down,
          onTap: () => sendSpecialKey('Down'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'right':
        return ArrowKeyButton(
          icon: Icons.arrow_right,
          onTap: () => sendSpecialKey('Right'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'image':
        return SpecialKeysImageButton(
          onTap: onImagePickRequested,
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'di_toggle':
        return DirectInputToggleButton(
          isEnabled: directInputEnabled,
          onTap: onDirectInputToggle,
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'input':
        return SizedBox(width: 64, child: CmdInputButton(onTap: onInputTap));
      case 'num1':
        return NumberKeyButton(
          label: '1',
          onTap: () => sendLiteralKey('1'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'num2':
        return NumberKeyButton(
          label: '2',
          onTap: () => sendLiteralKey('2'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'num3':
        return NumberKeyButton(
          label: '3',
          onTap: () => sendLiteralKey('3'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      case 'num4':
        return NumberKeyButton(
          label: '4',
          onTap: () => sendLiteralKey('4'),
          hapticFeedback: callbacks.hapticFeedback,
        );
      default:
        final button = _buttonForToken(token);
        if (button == null) return const SizedBox.shrink();
        return SizedBox(
          width: _labelWidth(button.label),
          child: _buildCustomKeyButton(button, height: height),
        );
    }
  }

  /// カスタムボタンのトークン解決（`ck:<id-suffix>` → CustomKeyButton）
  CustomKeyButton? _buttonForToken(String token) {
    if (!CustomKeyRows.isCustomToken(token)) return null;
    final id = 'ck_${token.substring(3)}';
    for (final b in customButtons) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// ラベル長に応じたカスタムボタン幅（44〜96px）
  double _labelWidth(String label) =>
      (label.length * 7.0 + 14.0).clamp(44.0, 96.0).toDouble();

  /// カスタムボタン：タップ時にソフトウェア修飾子をリセットしてから送信
  Widget _buildCustomKeyButton(CustomKeyButton button, {double height = 32}) {
    return CustomKeyButtonWidget(
      button: button,
      height: height,
      onKeyPressed: (key) {
        modifiers.clearAll();
        callbacks.onKeyPressed(key);
      },
      onSpecialKeyPressed: (key) {
        modifiers.clearAll();
        callbacks.onSpecialKeyPressed(key);
      },
      onEdit: (b) => onCustomButtonEdit?.call(b),
      hapticFeedback: callbacks.hapticFeedback,
    );
  }
}
