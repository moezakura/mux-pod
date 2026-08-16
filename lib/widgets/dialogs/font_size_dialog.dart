// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';

/// フォントサイズ選択ダイアログ
class FontSizeDialog extends StatefulWidget {
  final double currentSize;

  const FontSizeDialog({super.key, required this.currentSize});

  @override
  State<FontSizeDialog> createState() => _FontSizeDialogState();
}

class _FontSizeDialogState extends State<FontSizeDialog> {
  late double _selectedSize;

  static const List<double> _fontSizes = [10, 12, 14, 16, 18, 20];

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.currentSize;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.fontSizeTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _fontSizes.map((size) {
            return RadioListTile<double>(
              title: Text(size.toInt().toString()),
              value: size,
              groupValue: _selectedSize,
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
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}
