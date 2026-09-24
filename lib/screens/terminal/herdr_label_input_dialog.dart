import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_colors.dart';
import '../../l10n/l10n_ext.dart';

/// herdr の pane / tab ラベル入力ダイアログ（Q-02/Q-05: rename 解禁）。
///
/// tmux の RenameWindowDialog と違い、herdr のラベルは自由文字列
/// （`[a-zA-Z0-9_-]` 制約・重複チェックを持たない）ため、汎用のテキスト入力
/// ダイアログとして pane（`herdr pane rename`）と tab（`herdr tab rename`）の
/// 両方で共用する。空入力（trim 後）は無効。
class HerdrLabelInputDialog extends StatefulWidget {
  /// ダイアログタイトル（'Rename Pane' / 'Rename Tab'）。
  final String title;

  /// 入力欄のラベル（'Pane Label' / 'Tab Label'）。
  final String labelText;

  /// 入力欄のヒント（任意）。
  final String? hintText;

  /// 初期値（tab は現在ラベル。pane は domain にラベルが無いため空）。
  final String initialValue;

  /// 確定ボタンの文言（'Rename'）。
  final String confirmLabel;

  /// 空入力（trim 後）を許容するか（既定 false = rename の空不可挙動を維持。
  /// create のみ true で「空欄 = デフォルト名」を許容し、100 文字制限のみ課す）。
  final bool allowEmpty;

  const HerdrLabelInputDialog({
    super.key,
    required this.title,
    required this.labelText,
    this.hintText,
    this.initialValue = '',
    required this.confirmLabel,
    this.allowEmpty = false,
  });

  @override
  State<HerdrLabelInputDialog> createState() => HerdrLabelInputDialogState();
}

class HerdrLabelInputDialogState extends State<HerdrLabelInputDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateLabel(String? value) {
    final text = value ?? '';
    if (!widget.allowEmpty && text.trim().isEmpty) {
      return context.l10n.termLabelCannotBeEmpty;
    }
    if (text.length > 100) {
      return context.l10n.termLabelTooLong;
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _nameController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.title,
        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            hintStyle: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              color: isDark
                  ? DesignColors.textMuted
                  : DesignColors.textMutedLight,
            ),
            filled: true,
            fillColor: isDark
                ? DesignColors.inputDark
                : DesignColors.inputLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.error),
            ),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 14),
          validator: _validateLabel,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.termCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
