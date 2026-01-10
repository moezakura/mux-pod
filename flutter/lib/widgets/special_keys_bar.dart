import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 特殊キーの定義
class SpecialKeyDef {
  final String label;
  final TerminalKey? key;
  final String? text;
  final bool ctrl;
  final bool alt;
  final bool shift;

  const SpecialKeyDef({
    required this.label,
    this.key,
    this.text,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
  });
}

/// 特殊キーバーウィジェット
///
/// ESC, Tab, Ctrl+C などの特殊キーをタップで送信できるツールバー。
class SpecialKeysBar extends StatefulWidget {
  const SpecialKeysBar({
    super.key,
    required this.onKeyPressed,
    required this.onTextInput,
    this.backgroundColor,
  });

  final void Function(TerminalKey key, {bool ctrl, bool alt, bool shift}) onKeyPressed;
  final void Function(String text) onTextInput;
  final Color? backgroundColor;

  @override
  State<SpecialKeysBar> createState() => _SpecialKeysBarState();
}

class _SpecialKeysBarState extends State<SpecialKeysBar> {
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _shiftPressed = false;

  // 基本的な特殊キー
  static const List<SpecialKeyDef> _basicKeys = [
    SpecialKeyDef(label: 'ESC', key: TerminalKey.escape),
    SpecialKeyDef(label: 'Tab', key: TerminalKey.tab),
    SpecialKeyDef(label: '↑', key: TerminalKey.arrowUp),
    SpecialKeyDef(label: '↓', key: TerminalKey.arrowDown),
    SpecialKeyDef(label: '←', key: TerminalKey.arrowLeft),
    SpecialKeyDef(label: '→', key: TerminalKey.arrowRight),
    SpecialKeyDef(label: 'Home', key: TerminalKey.home),
    SpecialKeyDef(label: 'End', key: TerminalKey.end),
    SpecialKeyDef(label: 'PgUp', key: TerminalKey.pageUp),
    SpecialKeyDef(label: 'PgDn', key: TerminalKey.pageDown),
  ];

  // Ctrl+キー
  static const List<SpecialKeyDef> _ctrlKeys = [
    SpecialKeyDef(label: 'C', text: '\x03', ctrl: true),  // Ctrl+C
    SpecialKeyDef(label: 'D', text: '\x04', ctrl: true),  // Ctrl+D
    SpecialKeyDef(label: 'Z', text: '\x1a', ctrl: true),  // Ctrl+Z
    SpecialKeyDef(label: 'L', text: '\x0c', ctrl: true),  // Ctrl+L
    SpecialKeyDef(label: 'A', text: '\x01', ctrl: true),  // Ctrl+A
    SpecialKeyDef(label: 'E', text: '\x05', ctrl: true),  // Ctrl+E
    SpecialKeyDef(label: 'K', text: '\x0b', ctrl: true),  // Ctrl+K
    SpecialKeyDef(label: 'U', text: '\x15', ctrl: true),  // Ctrl+U
    SpecialKeyDef(label: 'W', text: '\x17', ctrl: true),  // Ctrl+W
    SpecialKeyDef(label: 'R', text: '\x12', ctrl: true),  // Ctrl+R
  ];

  void _handleKeyTap(SpecialKeyDef keyDef) {
    if (keyDef.key != null) {
      widget.onKeyPressed(
        keyDef.key!,
        ctrl: _ctrlPressed || keyDef.ctrl,
        alt: _altPressed || keyDef.alt,
        shift: _shiftPressed || keyDef.shift,
      );
    } else if (keyDef.text != null) {
      widget.onTextInput(keyDef.text!);
    }

    // モディファイアをリセット
    if (_ctrlPressed || _altPressed || _shiftPressed) {
      setState(() {
        _ctrlPressed = false;
        _altPressed = false;
        _shiftPressed = false;
      });
    }
  }

  Widget _buildModifierButton({
    required String label,
    required bool isPressed,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: isPressed
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isPressed
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyButton(SpecialKeyDef keyDef) {
    final showCtrlIndicator = keyDef.ctrl && !_ctrlPressed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: () => _handleKeyTap(keyDef),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              showCtrlIndicator ? 'C-${keyDef.label}' : keyDef.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor ?? Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // モディファイアキー
            _buildModifierButton(
              label: 'Ctrl',
              isPressed: _ctrlPressed,
              onPressed: () => setState(() => _ctrlPressed = !_ctrlPressed),
            ),
            _buildModifierButton(
              label: 'Alt',
              isPressed: _altPressed,
              onPressed: () => setState(() => _altPressed = !_altPressed),
            ),
            _buildModifierButton(
              label: 'Shift',
              isPressed: _shiftPressed,
              onPressed: () => setState(() => _shiftPressed = !_shiftPressed),
            ),
            const SizedBox(width: 8),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4),
            const SizedBox(width: 8),
            // 基本キー
            ..._basicKeys.map(_buildKeyButton),
            const SizedBox(width: 8),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4),
            const SizedBox(width: 8),
            // Ctrlキー
            ..._ctrlKeys.map(_buildKeyButton),
          ],
        ),
      ),
    );
  }
}
