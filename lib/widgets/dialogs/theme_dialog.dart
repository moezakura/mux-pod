// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';

/// テーマ選択ダイアログ
class ThemeDialog extends StatelessWidget {
  final bool isDarkMode;

  const ThemeDialog({
    super.key,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.themeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<bool>(
            title: Text(l10n.themeDark),
            value: true,
            groupValue: isDarkMode,
            onChanged: (value) {
              if (value != null) {
                Navigator.pop(context, value);
              }
            },
          ),
          RadioListTile<bool>(
            title: Text(l10n.themeLight),
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
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}
