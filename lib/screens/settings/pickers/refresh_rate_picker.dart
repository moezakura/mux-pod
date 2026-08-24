// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// 最大リフレッシュレート選択ダイアログ。
Future<void> showRefreshRatePicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final l10n = context.l10n;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsMaxRefreshRate),
      children: [
        for (final entry in [
          (
            'auto',
            l10n.settingsRefreshRateAuto,
            l10n.settingsRefreshRateAutoDescription,
          ),
          ('120', '120 Hz', l10n.settingsRefreshRateCap(120)),
          ('90', '90 Hz', l10n.settingsRefreshRateCap(90)),
          ('60', '60 Hz', l10n.settingsRefreshRateCap(60)),
        ])
          RadioListTile<String>(
            title: Text(entry.$2),
            subtitle: Text(entry.$3),
            value: entry.$1,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setRefreshRate(v);
              }
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}