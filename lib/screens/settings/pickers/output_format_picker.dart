// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// 出力フォーマット（Original / PNG / JPEG）選択ダイアログ。
Future<void> showOutputFormatPicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final l10n = context.l10n;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsOutputFormat),
      children: [
        for (final format in ['original', 'png', 'jpeg'])
          RadioListTile<String>(
            title: Text(format.toUpperCase()),
            value: format,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setImageOutputFormat(v);
              }
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}