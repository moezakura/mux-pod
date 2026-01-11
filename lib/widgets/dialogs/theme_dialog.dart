import 'package:flutter/material.dart';

/// テーマ選択ダイアログ
class ThemeDialog extends StatelessWidget {
  final bool isDarkMode;

  const ThemeDialog({
    super.key,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Theme'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<bool>(
            title: const Text('Dark'),
            value: true,
            groupValue: isDarkMode,
            onChanged: (value) {
              if (value != null) {
                Navigator.pop(context, value);
              }
            },
          ),
          RadioListTile<bool>(
            title: const Text('Light'),
            value: false,
            groupValue: isDarkMode,
            onChanged: (value) {
              if (value != null) {
                Navigator.pop(context, value);
              }
            },
          ),
        ],
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
