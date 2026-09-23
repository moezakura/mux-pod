import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../theme/design_colors.dart';

/// 新規セッション/ワークスペース名入力ダイアログ
///
/// 元は接続一覧シェルの private `_NewSessionDialog`。接続カードの State
/// （`New Session` / `New Workspace` ボタン）から `showDialog<String>` で
/// 表示され、入力名を返す。
class NewSessionDialog extends StatefulWidget {
  final List<String> existingSessionNames;

  const NewSessionDialog({super.key, required this.existingSessionNames});

  @override
  State<NewSessionDialog> createState() => NewSessionDialogState();
}

class NewSessionDialogState extends State<NewSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _generateDefaultName());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _generateDefaultName() {
    int index = 1;
    while (widget.existingSessionNames.contains('session-$index')) {
      index++;
    }
    return 'session-$index';
  }

  String? _validateSessionName(String? value) {
    if (value == null || value.isEmpty) {
      return context.l10n.connSessionNameRequired;
    }
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value)) {
      return context.l10n.connSessionNameInvalidChars;
    }
    if (widget.existingSessionNames.contains(value)) {
      return context.l10n.connSessionNameExists(value);
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _nameController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        context.l10n.connNewSession,
        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.connSessionNameLabel,
            hintText: 'session-1',
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
          validator: _validateSessionName,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.connCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.connCreate)),
      ],
    );
  }
}
