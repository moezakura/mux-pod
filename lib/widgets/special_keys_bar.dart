import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_colors.dart';

/// 特殊キーバー（HTMLデザイン仕様準拠）
class SpecialKeysBar extends StatefulWidget {
  final void Function(String key) onKeyPressed;
  final VoidCallback? onInputTap;
  final bool hapticFeedback;

  const SpecialKeysBar({
    super.key,
    required this.onKeyPressed,
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
          _buildKeyButton('ESC', '\x1b'),
          _buildKeyButton('TAB', '\t'),
          _buildModifierButton('CTRL', _ctrlPressed, () {
            setState(() => _ctrlPressed = !_ctrlPressed);
          }),
          _buildKeyButton('ALT', '\x1b', isModifier: true, isActive: _altPressed, onTap: () {
            setState(() => _altPressed = !_altPressed);
          }),
          _buildKeyButton('/', '/'),
          _buildKeyButton('-', '-'),
          _buildKeyButton('|', '|'),
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
          // 左矢印
          _buildArrowButton(Icons.arrow_left, '\x1b[D'),
          const SizedBox(width: 2),
          // 上下矢印スタック
          Column(
            children: [
              _buildSmallArrowButton(Icons.arrow_drop_up, '\x1b[A'),
              const SizedBox(height: 2),
              _buildSmallArrowButton(Icons.arrow_drop_down, '\x1b[B'),
            ],
          ),
          const SizedBox(width: 2),
          // 右矢印
          _buildArrowButton(Icons.arrow_right, '\x1b[C'),
          const SizedBox(width: 8),
          // Input ボタン
          Expanded(child: _buildInputButton()),
          const SizedBox(width: 8),
          // + ボタン
          _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildKeyButton(
    String label,
    String key, {
    bool isModifier = false,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    final isPrimary = label == 'CTRL' && _ctrlPressed;

    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () {
          if (onTap != null) {
            onTap();
          } else if (!isModifier) {
            _sendKey(key);
          }
        },
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? DesignColors.primary : DesignColors.keyBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: isActive ? DesignColors.primary : Colors.black,
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
                color: isPrimary || isActive
                    ? Colors.black
                    : (label == 'CTRL' ? DesignColors.primary : Colors.white.withValues(alpha: 0.9)),
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

  Widget _buildArrowButton(IconData icon, String key) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: () => _sendKey(key),
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

  Widget _buildSmallArrowButton(IconData icon, String key) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: () => _sendKey(key),
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

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: () {
        // TODO: Add new pane/window
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: DesignColors.keyBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: const Icon(
          Icons.add,
          size: 18,
          color: Colors.white,
        ),
      ),
    );
  }

  void _sendKey(String key) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    String modifiedKey = key;

    // CTRL修飾子を適用
    if (_ctrlPressed && key.length == 1) {
      final code = key.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7a) {
        // a-z -> Ctrl+A-Z (0x01-0x1a)
        modifiedKey = String.fromCharCode(code - 0x60);
      } else if (code >= 0x41 && code <= 0x5a) {
        // A-Z -> Ctrl+A-Z (0x01-0x1a)
        modifiedKey = String.fromCharCode(code - 0x40);
      }
      setState(() => _ctrlPressed = false);
    }

    // ALT修飾子を適用
    if (_altPressed) {
      modifiedKey = '\x1b$modifiedKey';
      setState(() => _altPressed = false);
    }

    widget.onKeyPressed(modifiedKey);
  }
}
