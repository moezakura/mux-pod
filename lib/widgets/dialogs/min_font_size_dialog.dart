// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';

/// 最小フォントサイズ選択ダイアログ
///
/// ターミナル自動フィット時の最小フォントサイズを選択する。
/// この値を下回る場合は水平スクロールが有効になる。
class MinFontSizeDialog extends StatefulWidget {
  final double currentSize;

  const MinFontSizeDialog({
    super.key,
    required this.currentSize,
  });

  @override
  State<MinFontSizeDialog> createState() => _MinFontSizeDialogState();
}

class _MinFontSizeDialogState extends State<MinFontSizeDialog> {
  late double _selectedSize;

  // 最小フォントサイズの選択肢（6〜12pt）
  static const List<double> _minFontSizes = [6, 7, 8, 9, 10, 11, 12];

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.currentSize;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.minFontSizeTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                l10n.minFontSizeDescription,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            ..._minFontSizes.map((size) {
              return RadioListTile<double>(
                title: Text('${size.toInt()} pt'),
                value: size,
                groupValue: _selectedSize,
                onChanged: (value) {
                  if (value != null) {
                    Navigator.pop(context, value);
                  }
                },
              );
            }),
          ],
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
