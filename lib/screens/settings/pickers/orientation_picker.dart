// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// 画面向き選択ダイアログ。
Future<void> showOrientationPicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final l10n = context.l10n;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsScreenOrientation),
      children: [
        for (final entry in [
          (
            'auto',
            l10n.settingsOrientationAuto,
            l10n.settingsOrientationAutoDescription,
          ),
          (
            'portrait',
            l10n.settingsOrientationPortrait,
            l10n.settingsOrientationPortraitDescription,
          ),
          (
            'landscape',
            l10n.settingsOrientationLandscape,
            l10n.settingsOrientationLandscapeDescription,
          ),
        ])
          RadioListTile<String>(
            title: Text(entry.$2),
            subtitle: Text(entry.$3),
            value: entry.$1,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setScreenOrientation(v);
              }
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}
