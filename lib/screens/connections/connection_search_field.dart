import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../theme/design_colors.dart';

/// 検索テキストフィールド（IME・controller 所有）。
///
/// 元は接続一覧シェルの private `_SearchField`。一覧シェルの AppBar から
/// 呼び出される。`didUpdateWidget` の「initialValue が空になったら clear」
/// 分岐（検索を閉じる際のクリア）を現行どおり維持する。
class SearchField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const SearchField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<SearchField> createState() => SearchFieldState();
}

class SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text &&
        widget.initialValue.isEmpty) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      autofocus: true,
      onChanged: widget.onChanged,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        color: colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: context.l10n.connSearchHint,
        hintStyle: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
        ),
        filled: true,
        fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1),
        ),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _controller.clear();
                  widget.onClear();
                },
                color: isDark
                    ? DesignColors.textMuted
                    : DesignColors.textMutedLight,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            : null,
      ),
    );
  }
}
