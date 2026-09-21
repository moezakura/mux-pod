import 'package:flutter/services.dart';

/// tmuxキー名の合成。
///
/// ソフトウェア修飾子接頭辞（S,C,M順・BTab特別扱い）、ハードウェア修飾子検出
/// （[HardwareKeyboard.instance] 読み取り）、LogicalKeyboardKey→tmuxキー静的表を
/// 担当する。純粋なのは [composeSpecial] / [composeLiteral] / [hwSpecialKeyMap]
/// のみで、[applyHardwareModifiers] は flutter/services 依存のため単体テスト不能。
class SpecialKeysTmuxComposer {
  const SpecialKeysTmuxComposer();

  /// 特殊キー名をソフトウェア修飾子と合成する（tmux形式）。
  ///
  /// - 特殊ケース: Shift+Tab → BTab（Back Tab）。
  /// - 修飾子は S, C, M の順に結合（例: S-Enter, C-M-a）。
  /// - 修飾子が無ければ [baseKey] をそのまま返す。
  String composeSpecial(
    String baseKey, {
    required bool shift,
    required bool ctrl,
    required bool alt,
  }) {
    // 特殊なケース: Shift+Tab → BTab (Back Tab)
    if (shift && baseKey == 'Tab') return 'BTab';

    // 修飾子を組み合わせる（Shift, Ctrl, Alt順）
    final modifiers = <String>[];
    if (shift) modifiers.add('S');
    if (ctrl) modifiers.add('C');
    if (alt) modifiers.add('M');

    // tmux形式で修飾子を適用
    if (modifiers.isEmpty) return baseKey;
    return '${modifiers.join('-')}-$baseKey';
  }

  /// リテラルキーをtmux形式に合成する。
  ///
  /// 修飾子がありキーが単文字の場合のみ tmux キー名（例: C-a）を返し、
  /// それ以外（修飾子なし・複数文字）は null を返す（リテラル送信）。
  String? composeLiteral(
    String key, {
    required bool shift,
    required bool ctrl,
    required bool alt,
  }) {
    // 修飾子を組み合わせる
    final modifiers = <String>[];
    if (shift) modifiers.add('S');
    if (ctrl) modifiers.add('C');
    if (alt) modifiers.add('M');

    // 修飾子がある場合はtmux形式で送信
    if (modifiers.isNotEmpty && key.length == 1) {
      return '${modifiers.join('-')}-$key';
    }
    return null;
  }

  /// 外付けキーボードの修飾子を検出してtmux形式キー名に変換
  String applyHardwareModifiers(String baseKey) {
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;

    // 特殊ケース: Shift+Tab → BTab
    if (isShift && baseKey == 'Tab') return 'BTab';

    final mods = <String>[];
    if (isShift) mods.add('S');
    if (isCtrl) mods.add('C');
    if (isAlt) mods.add('M');
    if (isMeta) mods.add('M');
    if (mods.isEmpty) return baseKey;
    return '${mods.join('-')}-$baseKey';
  }

  /// 外付けキーボード → tmuxキー名マッピング
  static final Map<LogicalKeyboardKey, String> hwSpecialKeyMap =
      <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.escape: 'Escape',
        LogicalKeyboardKey.tab: 'Tab',
        LogicalKeyboardKey.arrowUp: 'Up',
        LogicalKeyboardKey.arrowDown: 'Down',
        LogicalKeyboardKey.arrowLeft: 'Left',
        LogicalKeyboardKey.arrowRight: 'Right',
        LogicalKeyboardKey.home: 'Home',
        LogicalKeyboardKey.end: 'End',
        LogicalKeyboardKey.pageUp: 'PPage',
        LogicalKeyboardKey.pageDown: 'NPage',
        LogicalKeyboardKey.delete: 'DC',
        LogicalKeyboardKey.f1: 'F1',
        LogicalKeyboardKey.f2: 'F2',
        LogicalKeyboardKey.f3: 'F3',
        LogicalKeyboardKey.f4: 'F4',
        LogicalKeyboardKey.f5: 'F5',
        LogicalKeyboardKey.f6: 'F6',
        LogicalKeyboardKey.f7: 'F7',
        LogicalKeyboardKey.f8: 'F8',
        LogicalKeyboardKey.f9: 'F9',
        LogicalKeyboardKey.f10: 'F10',
        LogicalKeyboardKey.f11: 'F11',
        LogicalKeyboardKey.f12: 'F12',
      };
}
