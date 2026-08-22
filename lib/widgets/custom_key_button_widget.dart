import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/custom_keys/custom_key_button.dart';
import '../theme/design_colors.dart';

/// カスタムキーボタン：ラベルを表示し、タップでステップ列を順次実行する。
///
/// 標準の特殊キーボタン（シアン）と区別するため、枠線・文字をアンバー
/// （`DesignColors.secondary`）で描画する。
class CustomKeyButtonWidget extends StatefulWidget {
  const CustomKeyButtonWidget({
    super.key,
    required this.button, // CustomKeyButton
    required this.onKeyPressed, // void Function(String)
    required this.onSpecialKeyPressed, // void Function(String)
    required this.onEdit, // void Function(CustomKeyButton)
    this.hapticFeedback = true,
    this.height = 32,
  });

  final CustomKeyButton button;
  final void Function(String) onKeyPressed;
  final void Function(String) onSpecialKeyPressed;
  final void Function(CustomKeyButton) onEdit;
  final bool hapticFeedback;
  final double height;

  @override
  State<CustomKeyButtonWidget> createState() => _CustomKeyButtonWidgetState();
}

class _CustomKeyButtonWidgetState extends State<CustomKeyButtonWidget> {
  bool _executing = false;

  Future<void> _execute() async {
    if (_executing) return;
    _executing = true;
    try {
      for (final step in widget.button.steps) {
        switch (step.type) {
          case CustomKeyStepType.text:
            widget.onKeyPressed(step.value);
          case CustomKeyStepType.key:
            widget.onSpecialKeyPressed(step.value);
          case CustomKeyStepType.pause:
            final ms = int.tryParse(step.value.trim());
            if (ms != null && ms > 0) {
              await Future<void>.delayed(Duration(milliseconds: ms));
            }
        }
      }
    } finally {
      _executing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: _execute,
      onLongPress: () => widget.onEdit(widget.button),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: const Border(
            bottom: BorderSide(color: DesignColors.secondary, width: 2),
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
            widget.button.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: DesignColors.secondary,
            ),
          ),
        ),
      ),
    );
  }
}
