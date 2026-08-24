import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';

/// テキスト入力ダイアログ（任意文字列）。
Future<void> showTextInputDialog(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String currentValue,
  String? hint,
  required void Function(String) onSave,
}) async {
  final l10n = context.l10n;
  final controller = TextEditingController(text: currentValue);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            onSave(controller.text.trim());
            Navigator.pop(ctx);
          },
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
}

/// 数値入力ダイアログ。
Future<void> showNumberInputDialog(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required int currentValue,
  required void Function(int) onSave,
}) async {
  final l10n = context.l10n;
  final controller = TextEditingController(text: currentValue.toString());
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(controller.text.trim());
            if (v != null) onSave(v);
            Navigator.pop(ctx);
          },
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
}