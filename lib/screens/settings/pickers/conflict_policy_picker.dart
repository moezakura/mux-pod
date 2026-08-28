// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// ファイル名衝突ポリシー（確認 / 自動リネーム）選択ダイアログ（#41）。
///
/// `output_format_picker.dart` と同じ SimpleDialog + RadioListTile パターン。
Future<void> showConflictPolicyPicker(
  BuildContext context,
  WidgetRef ref,
  TransferConflictPolicy current,
) async {
  final l10n = context.l10n;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsUploadConflictPolicy),
      children: [
        for (final policy in TransferConflictPolicy.values)
          RadioListTile<TransferConflictPolicy>(
            title: Text(switch (policy) {
              TransferConflictPolicy.prompt =>
                l10n.settingsUploadConflictPrompt,
              TransferConflictPolicy.autoRename =>
                l10n.settingsUploadConflictAutoRename,
            }),
            value: policy,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setUploadConflictPolicy(v);
              }
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}
