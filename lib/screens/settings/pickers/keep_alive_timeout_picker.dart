// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';

/// 「自動」を表すダイアログ内のsentinel値（プリセットに含まれない）。
const int _autoValue = 0;

/// SSH キープアライブのプローブタイムアウト選択ダイアログ（自動 / 5〜60 秒）。
///
/// 選択は `setKeepAliveTimeoutSeconds` 経由で SharedPreferences
/// （settings_keep_alive_timeout）へ永続化される。「自動」は null（未設定）。
Future<void> showKeepAliveTimeoutPicker(
  BuildContext context,
  WidgetRef ref,
  int? current,
) async {
  final l10n = context.l10n;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsKeepAliveTimeout),
      children: [
        RadioListTile<int>(
          title: Text(l10n.settingsKeepAliveAuto),
          subtitle: Text(l10n.settingsKeepAliveTimeoutDescription),
          value: _autoValue,
          groupValue: current ?? _autoValue,
          onChanged: (v) {
            if (v != null) {
              ref
                  .read(settingsProvider.notifier)
                  .setKeepAliveTimeoutSeconds(null);
            }
            Navigator.pop(ctx);
          },
        ),
        for (final seconds in keepAliveTimeoutPresets)
          RadioListTile<int>(
            title: Text(l10n.settingsKeepAliveSeconds(seconds)),
            value: seconds,
            groupValue: current ?? _autoValue,
            onChanged: (v) {
              if (v != null) {
                ref
                    .read(settingsProvider.notifier)
                    .setKeepAliveTimeoutSeconds(v);
              }
              Navigator.pop(ctx);
            },
          ),
      ],
    ),
  );
}
