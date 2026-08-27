import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../services/sftp/overwrite_choice.dart';

/// 上書き確認ダイアログの結果。
///
/// [choice] はユーザーが選択した [OverwriteChoice]。
/// [applyToAll] は batch モードで「全ファイルに適用」がチェックされた場合のみ true。
///
/// 呼び出し規約:
/// - null 許容: [showOverwriteConfirmDialog] の戻り値は null を返し得る
///   （barrier/back で dismiss = 操作中断）。
/// - 失敗: throw しない（結果値で返す）。
/// - sync/async: async。
/// - 副作用: ダイアログ表示のみ。決定の適用（上書き/リネーム実行等）は呼び出し側（#40/#41）の責務。
class OverwriteConfirmResult {
  const OverwriteConfirmResult({required this.choice, this.applyToAll = false});

  final OverwriteChoice choice;

  /// batch モードで「全ファイルに適用」がチェックされたか。
  ///
  /// 契約 C-8: applyToAll = 選択した choice を**残り全衝突**に適用する
  /// （skip+applyToAll = 以降の全衝突をスキップして転送継続／
  ///   rename+applyToAll = 全衝突を自動リネーム）。
  final bool applyToAll;
}

/// 上書き確認ダイアログを表示する helper 関数。
///
/// `lib/screens/settings/pickers/clear_host_keys_confirmation.dart` の
/// helper 関数方式（`showDialog<T>` + AlertDialog + context.l10n）を踏襲する。
///
/// 表示する選択肢は [mode] で切り替わる:
/// - [OverwriteDialogMode.batch]（#40 用）: 上書き / リネーム / スキップ
///   + [showApplyToAll] が true のとき「全ファイルに適用」チェックボックス。
/// - [OverwriteDialogMode.single]（#41 用）: 上書き / リネーム / キャンセル。
///
/// 呼び出し規約:
/// - 戻り値: 選択確定時は [OverwriteConfirmResult]、dismiss（barrier/back）時は **null**。
///   null = 操作中断（batch ではバッチ中断 / single ではキャンセルと同義・契約 C-8）。
/// - 副作用: ダイアログ表示のみ。決定の適用は呼び出し側の責務。
Future<OverwriteConfirmResult?> showOverwriteConfirmDialog(
  BuildContext context, {
  required String fileName,
  OverwriteDialogMode mode = OverwriteDialogMode.single,
  bool showApplyToAll = false,
}) {
  final l10n = context.l10n;
  final isBatch = mode == OverwriteDialogMode.batch;
  var applyToAll = false;

  return showDialog<OverwriteConfirmResult>(
    context: context,
    builder: (dialogContext) {
      // batch モードの「全ファイルに適用」チェックボックスは StatefulBuilder で状態管理。
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text(l10n.fileOverwriteTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 長いファイル名は ellipsis で省略（OQ6）
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                  if (isBatch && showApplyToAll) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: applyToAll,
                      title: Text(l10n.fileApplyToAll),
                      onChanged: (v) => setState(() => applyToAll = v ?? false),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (isBatch)
                TextButton(
                  // #40 batch: 「スキップ」（個別継続）
                  onPressed: () => Navigator.of(dialogContext).pop(
                    OverwriteConfirmResult(
                      choice: OverwriteChoice.skip,
                      applyToAll: applyToAll,
                    ),
                  ),
                  child: Text(l10n.fileSkipAction),
                )
              else
                TextButton(
                  // #41 single: 「キャンセル」（全体中止）
                  onPressed: () => Navigator.of(dialogContext).pop(
                    const OverwriteConfirmResult(
                      choice: OverwriteChoice.cancel,
                    ),
                  ),
                  child: Text(l10n.commonCancel),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  OverwriteConfirmResult(
                    choice: OverwriteChoice.rename,
                    applyToAll: applyToAll,
                  ),
                ),
                child: Text(l10n.fileRenameAction),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  OverwriteConfirmResult(
                    choice: OverwriteChoice.overwrite,
                    applyToAll: applyToAll,
                  ),
                ),
                child: Text(l10n.fileOverwriteAction),
              ),
            ],
          );
        },
      );
    },
  );
}
