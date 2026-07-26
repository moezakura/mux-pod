import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_colors.dart';

/// ウィンドウ名変更ダイアログ
class RenameWindowDialog extends StatefulWidget {
  final String currentName;
  final List<String> otherWindowNames;

  const RenameWindowDialog({
    super.key,
    required this.currentName,
    required this.otherWindowNames,
  });

  @override
  State<RenameWindowDialog> createState() => _RenameWindowDialogState();
}

class _RenameWindowDialogState extends State<RenameWindowDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateWindowName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Window name cannot be empty';
    }
    if (value.length > 50) {
      return 'Window name must be 50 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      return 'Only letters, numbers, - and _ allowed';
    }
    if (widget.otherWindowNames.contains(value)) {
      return 'Window "$value" already exists';
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
        'Rename Window',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(
            labelText: 'Window Name',
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
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 14),
          validator: _validateWindowName,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
