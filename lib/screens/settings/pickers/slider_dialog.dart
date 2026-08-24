import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';

/// スライダー付きダイアログ（JPEG Quality 等）。
Future<void> showSliderDialog(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required double value,
  required double min,
  required double max,
  required void Function(double) onSave,
}) async {
  final l10n = context.l10n;
  var current = value;
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: current,
              min: min,
              max: max,
              onChanged: (v) => setState(() => current = v),
            ),
            Text('${current.round()}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              onSave(current);
              Navigator.pop(ctx);
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    ),
  );
}
