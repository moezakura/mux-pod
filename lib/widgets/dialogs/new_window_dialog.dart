import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_colors.dart';

/// 新規ウィンドウ作成ダイアログの入力値
///
/// 未入力の項目は `null` になる。
class NewWindowRequest {
  final String? name;
  final String? command;

  const NewWindowRequest({this.name, this.command});
}

/// 新規ウィンドウ作成ダイアログ
class NewWindowDialog extends StatefulWidget {
  final List<String> existingWindowNames;

  const NewWindowDialog({super.key, required this.existingWindowNames});

  @override
  State<NewWindowDialog> createState() => _NewWindowDialogState();
}

class _NewWindowDialogState extends State<NewWindowDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  String? _validateWindowName(String? value) {
    if (value == null || value.isEmpty) {
      return null; // 空入力はtmuxデフォルト名で許容
    }
    if (value.length > 50) {
      return 'Window name must be 50 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      return 'Only letters, numbers, - and _ allowed';
    }
    if (widget.existingWindowNames.contains(value)) {
      return 'Window "$value" already exists';
    }
    return null;
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(
        context,
        NewWindowRequest(
          name: _nullIfEmpty(_nameController.text),
          command: _nullIfEmpty(_commandController.text),
        ),
      );
    }
  }

  InputDecoration _decoration({
    required bool isDark,
    required ColorScheme colorScheme,
    required String labelText,
    required String hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      hintStyle: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
      ),
      filled: true,
      fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final fieldStyle = GoogleFonts.jetBrainsMono(fontSize: 14);
    return AlertDialog(
      title: Text(
        'New Window',
        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                maxLength: 50,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                decoration: _decoration(
                  isDark: isDark,
                  colorScheme: colorScheme,
                  labelText: 'Window Name',
                  hintText: 'Leave empty for default',
                ),
                style: fieldStyle,
                validator: _validateWindowName,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _commandController,
                maxLines: 1,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                decoration: _decoration(
                  isDark: isDark,
                  colorScheme: colorScheme,
                  labelText: 'Command',
                  hintText: 'npm run dev (optional)',
                ),
                style: fieldStyle,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
