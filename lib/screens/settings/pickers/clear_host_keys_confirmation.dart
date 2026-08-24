import 'package:flutter/material.dart';

import '../../../services/keychain/secure_storage.dart';

/// SSHホスト鍵フィンガープリントを全て消去する（確認付き）。
///
/// サーバーのホスト鍵が変わった / 保存状態が壊れた場合の復旧手段。
/// アプリデータ全体を消すより軽く、次回接続でホスト鍵を再受諾できる。
/// 文言の l10n 化は P1-C4 で実施する（現状は英語直書き）。
Future<void> confirmClearHostKeys(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clear SSH host keys?'),
      content: const Text(
        'This removes all saved server host-key fingerprints. The next '
        'connection silently trusts and re-saves whatever host key each '
        'server presents, so only do this on a network you trust.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  // 削除は mounted チェックより前に走らせる: 画面が閉じても、確認済みの
  // 意図は実行する。mounted は SnackBar の表示だけを守る。
  String message;
  try {
    final removed = await SecureStorageService()
        .deleteAllHostKeyFingerprints();
    message = removed == 0
        ? 'No saved host keys to clear'
        : 'Cleared $removed saved host key${removed == 1 ? '' : 's'}';
  } catch (e) {
    message = 'Could not clear host keys: ${e.runtimeType}';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}