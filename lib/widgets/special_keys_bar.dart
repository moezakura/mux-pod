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

  const SpecialKeysBar({
    super.key,
    required this.onKeyPressed,
    required this.onSpecialKeyPressed,
    this.onInputTap,
    this.hapticFeedback = true,
  });

  @override
  State<SpecialKeysBar> createState() => _SpecialKeysBarState();
}

class _SpecialKeysBarState extends State<SpecialKeysBar> {
  bool _ctrlPressed = false;
  bool _altPressed = false;

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

  /// 上部の修飾キー行（ESC, TAB, CTRL, ALT, /, -, |）
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
          _buildLiteralKeyButton('/', '/'),
          _buildLiteralKeyButton('-', '-'),
          _buildLiteralKeyButton('|', '|'),
        ],
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
          // Input ボタン
          Expanded(child: _buildInputButton()),
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

    // CTRL修飾子を適用（tmux形式: C-キー）
    if (_ctrlPressed) {
      // tmux形式では C-a, C-b などで表現
      if (tmuxKey.length == 1) {
        key = 'C-$tmuxKey';
      }
      setState(() => _ctrlPressed = false);
    }

    // ALT修飾子を適用（tmux形式: M-キー）
    if (_altPressed) {
      // tmux形式では M-a, M-b などで表現
      if (tmuxKey.length == 1) {
        key = 'M-$tmuxKey';
      } else {
        // 特殊キーの場合はそのまま送信
        key = 'M-$tmuxKey';
      }
      setState(() => _altPressed = false);
    }

    widget.onSpecialKeyPressed(key);
  }

  /// リテラルキーを送信（文字そのまま）
  void _sendLiteralKey(String key) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    // CTRL修飾子を適用
    if (_ctrlPressed && key.length == 1) {
      // tmux形式: C-/等
      widget.onSpecialKeyPressed('C-$key');
      setState(() => _ctrlPressed = false);
      return;
    }

    // ALT修飾子を適用
    if (_altPressed && key.length == 1) {
      // tmux形式: M-/等
      widget.onSpecialKeyPressed('M-$key');
      setState(() => _altPressed = false);
      return;
    }

    // 修飾子なしの場合はリテラル送信
    widget.onKeyPressed(key);
  }
}
