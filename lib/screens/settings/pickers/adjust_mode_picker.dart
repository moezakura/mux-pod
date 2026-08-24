// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// 調整モード選択ダイアログ（RadioListTile 使用のため限定 ignore）。
Future<void> showAdjustModePicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final l10n = context.l10n;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsAdjustMode),
      children: [
        for (final entry in [
          (
            'none',
            l10n.settingsAdjustModeNone,
            l10n.settingsAdjustModeNoneDescription,
          ),
          (
            'autoFit',
            l10n.settingsAdjustModeAutoFit,
            l10n.settingsAdjustModeAutoFitDescription,
          ),
          (
            'autoResize',
            l10n.settingsAdjustModeAutoResize,
            l10n.settingsAdjustModeAutoResizeDescription,
          ),
        ])
          RadioListTile<String>(
            title: Text(entry.$2),
            subtitle: Text(entry.$3),
            value: entry.$1,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setAdjustMode(v);
              }
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}