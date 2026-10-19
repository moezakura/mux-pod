import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

/// OSC 8 リンクタップ時の確認モーダル（🤝#3・Issue #61）。
///
/// URL 全文を [SelectableText] で表示し、ユーザーが開く前に確認・コピー
/// できる（誤タップ・フィッシング＝表示テキスト ≠ href の緩和策）。
///
/// 戻り値契約（§L4 モーダル行）:
/// - `true` = 「開く」承認
/// - `false` = 「キャンセル」またはスキャン外タップによる dismiss
/// - throw しない（async・副作用: モーダル表示のみ）
Future<bool> confirmExternalLink(BuildContext context, Uri uri) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.termLinkConfirmTitle),
      content: SelectableText(uri.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.l10n.termLinkConfirmCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(context.l10n.termLinkConfirmOpen),
        ),
      ],
    ),
  );
  return result ?? false;
}
