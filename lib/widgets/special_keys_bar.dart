import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_colors.dart';

/// 特殊キーバー（HTMLデザイン仕様準拠）
///
/// tmuxコマンド方式でキーを送信するため、
/// tmux send-keys形式のキー名を使用する。
class SpecialKeysBar extends StatefulWidget {
  /// リテラルキー送信（通常の文字）
  final void Function(String key) onKeyPressed;

  /// 特殊キー送信（tmux形式: Enter, Escape, C-c等）
  final void Function(String tmuxKey) onSpecialKeyPressed;

  final VoidCallback? onInputTap;
  final bool hapticFeedback;

  /// DirectInputモードが有効か
  final bool directInputEnabled;

  /// DirectInputモードのトグルコールバック
  final VoidCallback? onDirectInputToggle;

  const SpecialKeysBar({
    super.key,
    required this.onKeyPressed,
    required this.onSpecialKeyPressed,
    this.onInputTap,
    this.hapticFeedback = true,
    this.directInputEnabled = false,
    this.onDirectInputToggle,
  });

  @override
  State<SpecialKeysBar> createState() => _SpecialKeysBarState();
}

class _SpecialKeysBarState extends State<SpecialKeysBar> {
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _shiftPressed = false;
  final TextEditingController _directInputController = TextEditingController();
  final FocusNode _directInputFocusNode = FocusNode();

  /// 前回送信済みのテキスト（IME確定検出用）
  String _lastSentText = '';

  /// 現在IME変換中かどうか
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _directInputController.addListener(_onDirectInputChanged);
  }

  @override
  void dispose() {
    _directInputController.removeListener(_onDirectInputChanged);
    _directInputController.dispose();
    _directInputFocusNode.dispose();
    super.dispose();
  }

  /// DirectInput: IME変換確定時のみ送信
  void _onDirectInputChanged() {
    final text = _directInputController.text;
    final value = _directInputController.value;

    // composingが空でない = IME変換中
    _isComposing = value.composing.isValid && !value.composing.isCollapsed;

    if (_isComposing) {
      // 変換中は送信しない
      return;
    }

    // 新しく追加された文字のみを送信
    if (text.length > _lastSentText.length) {
      final newText = text.substring(_lastSentText.length);

      // CTRLボタンが押されている場合はCtrl+キーとして送信
      if (_ctrlPressed && newText.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(newText)) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        widget.onSpecialKeyPressed('C-${newText.toLowerCase()}');
        // 入力をクリアしてCTRL状態をリセット
        _directInputController.clear();
        _lastSentText = '';
        setState(() => _ctrlPressed = false);
        return;
      }

      widget.onKeyPressed(newText);
    }
    _lastSentText = text;

    // テキストが長くなりすぎたらクリア（100文字を超えたら）
    if (text.length > 100) {
      _directInputController.clear();
      _lastSentText = '';
    }
  }

  /// DirectInput: ソフトウェアキーボードのEnter（送信）で呼ばれる
  void _onDirectInputSubmitted(String value) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    widget.onSpecialKeyPressed('Enter');
    // 入力欄をクリア
    _directInputController.clear();
    _lastSentText = '';
  }

  /// DirectInput: Backspaceキー送信
  void _sendDirectBackspace() {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    widget.onSpecialKeyPressed('BSpace');
  }

  /// キーイベントハンドラ（Enter/Backspace/Ctrl+キー等をキャプチャ）
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // IME変換中はキーイベントを処理しない
    if (_isComposing) {
      return KeyEventResult.ignored;
    }

    // Ctrl/Meta修飾キーの検出
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Ctrl+キーのショートカット処理
    if (isCtrlPressed) {
      final keyLabel = event.logicalKey.keyLabel;
      // A-Z の単一キーの場合、Ctrl+キーとしてtmuxに送信
      if (keyLabel.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(keyLabel)) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        // tmux形式: C-c, C-d など（小文字）
        widget.onSpecialKeyPressed('C-${keyLabel.toLowerCase()}');
        return KeyEventResult.handled;
      }
    }

    // Enterキー
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _sendDirectEnterAndClear();
      return KeyEventResult.handled;
    }

    // Backspaceキー（テキストが空の場合のみ送信）
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_directInputController.text.isEmpty) {
        _sendDirectBackspace();
        return KeyEventResult.handled;
      }
    }

    // Escapeキー
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.hapticFeedback) {
        HapticFeedback.lightImpact();
      }
      widget.onSpecialKeyPressed('Escape');
      return KeyEventResult.handled;
    }

    // Tabキー
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (widget.hapticFeedback) {
        HapticFeedback.lightImpact();
      }
      widget.onSpecialKeyPressed('Tab');
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// DirectInput: Enterキー送信して入力欄をクリア
  void _sendDirectEnterAndClear() {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    widget.onSpecialKeyPressed('Enter');
    // 入力欄をクリア
    _directInputController.clear();
    _lastSentText = '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DesignColors.footerBackground : DesignColors.footerBackgroundLight,
        border: Border(
          top: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModifierKeysRow(),
            _buildArrowKeysRow(),
            if (widget.directInputEnabled) _buildDirectInputRow(),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// 上部の修飾キー行（ESC, TAB, CTRL, ALT, SHIFT, ENTER, S-RET, /, -）
  Widget _buildModifierKeysRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
      child: Row(
        children: [
          _buildSpecialKeyButton('ESC', 'Escape'),
          _buildSpecialKeyButton('TAB', 'Tab'),
          _buildModifierButton('CTRL', _ctrlPressed, () {
            setState(() => _ctrlPressed = !_ctrlPressed);
          }),
          _buildModifierButton('ALT', _altPressed, () {
            setState(() => _altPressed = !_altPressed);
          }),
          _buildModifierButton('SHIFT', _shiftPressed, () {
            setState(() => _shiftPressed = !_shiftPressed);
          }),
          _buildEnterKeyButton(),
          _buildShiftEnterKeyButton(),
          _buildLiteralKeyButton('/', '/'),
          _buildLiteralKeyButton('-', '-'),
        ],
      ),
    );
  }

  /// Shift+Enterキーボタン（Claude CodeのAcceptEdits等用）
  Widget _buildShiftEnterKeyButton() {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendSpecialKey('S-Enter'),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: DesignColors.secondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(color: DesignColors.secondary.withValues(alpha: 0.5), width: 2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'S-RET',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: DesignColors.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ENTERキーボタン（単体でEnterを送信）
  Widget _buildEnterKeyButton() {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendSpecialKey('Enter'),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: DesignColors.primary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(color: DesignColors.primary.withValues(alpha: 0.5), width: 2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_return,
                  size: 12,
                  color: DesignColors.primary,
                ),
                const SizedBox(width: 2),
                Text(
                  'RET',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 下部の矢印キー + Inputボタン行
  Widget _buildArrowKeysRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // 左矢印 (tmux: Left)
          _buildArrowButton(Icons.arrow_left, 'Left'),
          const SizedBox(width: 2),
          // 上下矢印スタック
          Column(
            children: [
              _buildSmallArrowButton(Icons.arrow_drop_up, 'Up'),
              const SizedBox(height: 2),
              _buildSmallArrowButton(Icons.arrow_drop_down, 'Down'),
            ],
          ),
          const SizedBox(width: 2),
          // 右矢印 (tmux: Right)
          _buildArrowButton(Icons.arrow_right, 'Right'),
          const SizedBox(width: 8),
          // DirectInputモードトグルボタン
          _buildDirectInputToggle(),
          const SizedBox(width: 4),
          // DirectInputモードが無効の場合のみInputボタンを表示
          if (!widget.directInputEnabled)
            Expanded(child: _buildInputButton()),
        ],
      ),
    );
  }

  /// DirectInput専用行（入力フィールドのみ）
  /// RET/BSはネイティブキーボードのものを使用
  Widget _buildDirectInputRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: _buildDirectInputField(),
    );
  }

  /// DirectInputモードのトグルボタン
  Widget _buildDirectInputToggle() {
    final isEnabled = widget.directInputEnabled;
    return GestureDetector(
      onTap: () {
        if (widget.hapticFeedback) {
          HapticFeedback.selectionClick();
        }
        widget.onDirectInputToggle?.call();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isEnabled
              ? DesignColors.success.withValues(alpha: 0.3)
              : DesignColors.keyBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isEnabled
                ? DesignColors.success.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Center(
          child: Icon(
            isEnabled ? Icons.flash_on : Icons.flash_off,
            size: 18,
            color: isEnabled ? DesignColors.success : Colors.white70,
          ),
        ),
      ),
    );
  }

  /// DirectInput用テキストフィールド（リアルタイム送信）
  Widget _buildDirectInputField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: DesignColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: DesignColors.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            // LIVEインジケーター（左側に配置）
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: DesignColors.success.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: DesignColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: DesignColors.success.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 入力フィールド
            Expanded(
              child: TextField(
                controller: _directInputController,
                focusNode: _directInputFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.send,
                onSubmitted: _onDirectInputSubmitted,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Type here...',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: DesignColors.success.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 特殊キーボタン（tmux形式で送信）
  Widget _buildSpecialKeyButton(String label, String tmuxKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendSpecialKey(tmuxKey),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isDark ? DesignColors.keyBackground : DesignColors.keyBackgroundLight,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(color: isDark ? Colors.black : Colors.grey.shade400, width: 2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// リテラルキーボタン（そのまま文字として送信）
  Widget _buildLiteralKeyButton(String label, String key) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendLiteralKey(key),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isDark ? DesignColors.keyBackground : DesignColors.keyBackgroundLight,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(color: isDark ? Colors.black : Colors.grey.shade400, width: 2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModifierButton(String label, bool isPressed, VoidCallback onPressed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: onPressed,
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isPressed ? colorScheme.primary : (isDark ? DesignColors.keyBackground : DesignColors.keyBackgroundLight),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: isPressed ? colorScheme.primary : (isDark ? Colors.black : Colors.grey.shade400),
                width: 2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isPressed ? colorScheme.onPrimary : colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrowButton(IconData icon, String tmuxKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: () => _sendSpecialKey(tmuxKey),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? DesignColors.keyBackground : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Icon(
          icon,
          size: 16,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildSmallArrowButton(IconData icon, String tmuxKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: () => _sendSpecialKey(tmuxKey),
      child: Container(
        width: 36,
        height: 17,
        decoration: BoxDecoration(
          color: isDark ? DesignColors.keyBackground : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Icon(
          icon,
          size: 14,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildInputButton() {
    return GestureDetector(
      onTap: widget.onInputTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: DesignColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: DesignColors.primary.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.keyboard,
              size: 16,
              color: DesignColors.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Input...',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: DesignColors.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: DesignColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: DesignColors.primary.withValues(alpha: 0.1)),
              ),
              child: Text(
                'cmd',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: DesignColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 特殊キーを送信（tmux形式）
  void _sendSpecialKey(String tmuxKey) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    String key = tmuxKey;

    // 特殊なケース: Shift+Tab → BTab (Back Tab)
    if (_shiftPressed && tmuxKey == 'Tab') {
      setState(() => _shiftPressed = false);
      // Ctrl/Altの状態もリセット
      if (_ctrlPressed) setState(() => _ctrlPressed = false);
      if (_altPressed) setState(() => _altPressed = false);
      widget.onSpecialKeyPressed('BTab');
      return;
    }

    // 修飾子を組み合わせる（Shift, Ctrl, Alt順）
    final List<String> modifiers = [];
    if (_shiftPressed) {
      modifiers.add('S');
      setState(() => _shiftPressed = false);
    }
    if (_ctrlPressed) {
      modifiers.add('C');
      setState(() => _ctrlPressed = false);
    }
    if (_altPressed) {
      modifiers.add('M');
      setState(() => _altPressed = false);
    }

    // tmux形式で修飾子を適用
    if (modifiers.isNotEmpty) {
      // 例: S-Enter, C-M-a など
      final prefix = modifiers.join('-');
      key = '$prefix-$tmuxKey';
    }

    widget.onSpecialKeyPressed(key);
  }

  /// リテラルキーを送信（文字そのまま）
  void _sendLiteralKey(String key) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    // 修飾子を組み合わせる
    final List<String> modifiers = [];
    if (_shiftPressed) {
      modifiers.add('S');
      setState(() => _shiftPressed = false);
    }
    if (_ctrlPressed) {
      modifiers.add('C');
      setState(() => _ctrlPressed = false);
    }
    if (_altPressed) {
      modifiers.add('M');
      setState(() => _altPressed = false);
    }

    // 修飾子がある場合はtmux形式で送信
    if (modifiers.isNotEmpty && key.length == 1) {
      final prefix = modifiers.join('-');
      widget.onSpecialKeyPressed('$prefix-$key');
      return;
    }

    // 修飾子なしの場合はリテラル送信
    widget.onKeyPressed(key);
  }
}
