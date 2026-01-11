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

  /// DirectInput: 入力した文字を即座に送信
  void _onDirectInputChanged() {
    final text = _directInputController.text;
    if (text.isNotEmpty) {
      // 最後の文字を送信
      widget.onKeyPressed(text);
      // 入力をクリア
      _directInputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DesignColors.footerBackground,
        border: Border(
          top: BorderSide(color: Color(0xFF2A2B36), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModifierKeysRow(),
            _buildArrowKeysRow(),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// 上部の修飾キー行（ESC, TAB, CTRL, ALT, SHIFT, ENTER, S-RET, /, -）
  Widget _buildModifierKeysRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: DesignColors.surfaceDark,
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
          // DirectInputモードに応じて表示を切り替え
          Expanded(
            child: widget.directInputEnabled
                ? _buildDirectInputField()
                : _buildInputButton(),
          ),
        ],
      ),
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
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: DesignColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: DesignColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _directInputController,
              focusNode: _directInputFocusNode,
              autofocus: true,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText: 'Direct input...',
                hintStyle: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: DesignColors.success.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                isDense: true,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: DesignColors.success.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'LIVE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: DesignColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 特殊キーボタン（tmux形式で送信）
  Widget _buildSpecialKeyButton(String label, String tmuxKey) {
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
            color: DesignColors.keyBackground,
            borderRadius: BorderRadius.circular(4),
            border: const Border(
              bottom: BorderSide(color: Colors.black, width: 2),
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
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// リテラルキーボタン（そのまま文字として送信）
  Widget _buildLiteralKeyButton(String label, String key) {
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
            color: DesignColors.keyBackground,
            borderRadius: BorderRadius.circular(4),
            border: const Border(
              bottom: BorderSide(color: Colors.black, width: 2),
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
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModifierButton(String label, bool isPressed, VoidCallback onPressed) {
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
            color: isPressed ? DesignColors.primary : DesignColors.keyBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: isPressed ? DesignColors.primary : Colors.black,
                width: 2,
              ),
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
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isPressed ? Colors.black : DesignColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrowButton(IconData icon, String tmuxKey) {
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
          color: DesignColors.keyBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Icon(
          icon,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildSmallArrowButton(IconData icon, String tmuxKey) {
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
          color: DesignColors.keyBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Icon(
          icon,
          size: 14,
          color: Colors.white,
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
