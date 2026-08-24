// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// 言語設定ピッカー: System / 日本語 / English の3択。
Future<void> showLanguagePicker(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  showDialog(
    context: context,
    builder: (ctx) {
      final l10n = ctx.l10n;
      return SimpleDialog(
        title: Text(l10n.settingsLanguage),
        children: [
          for (final entry in [
            ('system', l10n.languageSystem, l10n.languageSystemDescription),
            ('ja', l10n.languageJapanese, null),
            ('en', l10n.languageEnglish, null),
          ])
            RadioListTile<String>(
              title: Text(entry.$2),
              subtitle: entry.$3 != null ? Text(entry.$3!) : null,
              value: entry.$1,
              groupValue: current,
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).setLanguage(v);
                }
                Navigator.pop(ctx);
              },
            ),
        ],
      );
    },
  );
}