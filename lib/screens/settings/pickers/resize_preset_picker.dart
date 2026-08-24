// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// リサイズプリセット選択ダイアログ。
Future<void> showResizePresetPicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final l10n = context.l10n;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsResizePreset),
      children: [
        for (final entry in [
          ('original', l10n.settingsResizePresetOriginal),
          ('small', l10n.settingsResizePresetSmall(480)),
          ('medium', l10n.settingsResizePresetMedium(1080)),
          ('large', l10n.settingsResizePresetLarge(1920)),
          ('custom', l10n.settingsResizePresetCustom),
        ])
          RadioListTile<String>(
            title: Text(entry.$2),
            value: entry.$1,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setImageResizePreset(v);
              }
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}
