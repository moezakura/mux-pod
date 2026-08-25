import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

// inventory: SETTINGS-UI-INPUT-002
/// Scroll Send Input 選択ダイアログ（Wheel / Key）。
///
/// RadioListTile は Flutter 3.32+ で deprecated のため新規には使わない
/// （Pattern Map D9 方針）。選択肢は ListTile 方式。
Future<void> showScrollSendInputPicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final l10n = ctx.l10n;
      return SimpleDialog(
        title: Text(l10n.settingsScrollSendInput),
        children: [
          _buildScrollSendOption(
            ctx,
            'wheel',
            l10n.settingsScrollSendPickWheel,
            l10n.settingsScrollSendPickWheelDesc,
            current,
          ),
          _buildScrollSendOption(
            ctx,
            'key',
            l10n.settingsScrollSendPickKey,
            l10n.settingsScrollSendPickKeyDesc,
            current,
          ),
        ],
      );
    },
  );
  if (result != null) {
    await ref.read(settingsProvider.notifier).setScrollSendInput(result);
  }
}

/// Scroll Send Input ダイアログの選択肢（選択中をハイライト + チェック表示）。
Widget _buildScrollSendOption(
  BuildContext context,
  String value,
  String label,
  String description,
  String currentValue,
) {
  final selected = value == currentValue;
  return ListTile(
    title: Text(label),
    subtitle: Text(description),
    selected: selected,
    trailing: selected ? const Icon(Icons.check) : null,
    onTap: () => Navigator.pop(context, value),
  );
}
