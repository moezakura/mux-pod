import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// キーオーバーレイ位置選択ダイアログ（Above Keyboard / Center / Below Header）。
Future<void> showOverlayPositionPicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final l10n = context.l10n;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsOverlayPosition),
      children: [
        _buildPositionOption(
          ctx,
          'aboveKeyboard',
          l10n.settingsOverlayPositionAboveKeyboard,
          current,
        ),
        _buildPositionOption(
          ctx,
          'center',
          l10n.settingsOverlayPositionCenter,
          current,
        ),
        _buildPositionOption(
          ctx,
          'belowHeader',
          l10n.settingsOverlayPositionBelowHeader,
          current,
        ),
      ],
    ),
  );
  if (result != null) {
    ref.read(settingsProvider.notifier).setKeyOverlayPosition(result);
  }
}

Widget _buildPositionOption(
  BuildContext context,
  String value,
  String label,
  String currentValue,
) {
  return SimpleDialogOption(
    onPressed: () => Navigator.pop(context, value),
    child: Row(
      children: [
        Icon(
          value == currentValue
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}