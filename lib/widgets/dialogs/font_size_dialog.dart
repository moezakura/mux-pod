import 'package:flutter/material.dart';

/// フォントサイズ選択ダイアログ
class FontSizeDialog extends StatefulWidget {
  final double currentSize;

  const FontSizeDialog({
    super.key,
    required this.currentSize,
  });

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
    return AlertDialog(
      title: const Text('Font Size'),
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
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
