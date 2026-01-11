import 'package:flutter/material.dart';

/// フォントファミリー選択ダイアログ
class FontFamilyDialog extends StatefulWidget {
  final String currentFamily;

  const FontFamilyDialog({
    super.key,
    required this.currentFamily,
  });

  @override
  State<FontFamilyDialog> createState() => _FontFamilyDialogState();
}

class _FontFamilyDialogState extends State<FontFamilyDialog> {
  late String _selectedFamily;

  static const List<String> _fontFamilies = [
    'JetBrains Mono',
    'Fira Code',
    'Source Code Pro',
    'Roboto Mono',
  ];

  @override
  void initState() {
    super.initState();
    _selectedFamily = widget.currentFamily;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Font Family'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _fontFamilies.map((family) {
            return RadioListTile<String>(
              title: Text(family),
              value: family,
              groupValue: _selectedFamily,
              onChanged: (value) {
                if (value != null) {
                  Navigator.pop(context, value);
                }
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
