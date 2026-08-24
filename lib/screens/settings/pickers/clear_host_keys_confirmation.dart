import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/keychain/secure_storage.dart';

/// SSHホスト鍵フィンガープリントを全て消去する（確認付き）。
///
/// サーバーのホスト鍵が変わった / 保存状態が壊れた場合の復旧手段。
/// アプリデータ全体を消すより軽く、次回接続でホスト鍵を再受諾できる。
Future<void> confirmClearHostKeys(BuildContext context) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.settingsClearHostKeysDialogTitle),
      content: Text(l10n.settingsClearHostKeysDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.settingsClearHostKeysCancelAction),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.settingsClearHostKeysConfirmAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  // 削除は mounted チェックより前に走らせる: 画面が閉じても、確認済みの
  // 意図は実行する。mounted は SnackBar の表示だけを守る。
  String message;
  try {
    await SecureStorageService().deleteAllHostKeyFingerprints();
    message = l10n.settingsClearHostKeysDone;
  } catch (e) {
    // 例外時のみのフォールバック文言（計画に l10n キー定義なし・P1-C4 申告事項）
    message = 'Could not clear host keys: ${e.runtimeType}';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
