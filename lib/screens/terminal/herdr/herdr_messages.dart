import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/backend/domain/pane_writer.dart';
import '../../../services/connection_error.dart';
import '../../../services/herdr/herdr_errors.dart';

/// H4: herdr SnackBar 系は **HEAD と同一（多重抑止なし）**。
/// dedup を追加すると文言/回数テスト（herdr UI・remaining_contracts）が壊れる。

/// herdr 用のエラー SnackBar（tmux の `_showErrorSnackBar` を踏襲）。
///
/// Retry は「再接続」ではなく「再試行」（再解決 / ポーリング再開）を意味する。
void herdrShowError(
  BuildContext context,
  String message, {
  required VoidCallback retry,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      action: SnackBarAction(
        label: context.l10n.termRetry,
        textColor: Colors.white,
        onPressed: retry,
      ),
    ),
  );
}

/// mutation の結果 SnackBar（プレーン通知。分類別の文言は呼び出し側が組み立てる）。
void herdrShowMutation(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// target-not-found の通知（SnackBar「対象が消えました。再同期しました」）。
void herdrShowTargetNotFound(BuildContext context) {
  herdrShowMutation(context, context.l10n.termHerdrTargetLost);
}

/// 非対応キー（`invalid_key`）の防御的通知。
void herdrShowInvalidKey(BuildContext context) {
  herdrShowMutation(context, context.l10n.termHerdrInvalidKey);
}

/// 方向なし / no-op（soft 失敗）の情報通知。
void herdrShowNoop(BuildContext context, PaneOperationNoopException e) {
  final l10n = context.l10n;
  final message = switch (e.reason) {
    'no_neighbor' => l10n.termHerdrNoNeighbor,
    'unchanged' => l10n.termHerdrUnchanged,
    _ => l10n.termHerdrNoopGeneric,
  };
  herdrShowMutation(context, message);
}

/// mutation 失敗の分類（S4 分類表）。
///
/// 通知・後続処理は各分類の分岐で行う（servers 側ルーティングは controller）。
enum HerdrMutationClass {
  /// `pane_not_found` 等 → 通知 + 再同期
  targetNotFound,

  /// `invalid_key`（防御的・通常発生しない）
  invalidKey,

  /// `no_neighbor` / `changed:false` の soft 失敗 → 情報通知のみ
  noop,

  /// server-down → ポーリング停止 + 通知 + キャッシュ失効
  serverDown,

  /// 接続断（`SshConnectionError`）→ 自動再接続
  sshDisconnected,

  /// その他通信エラー → エラー SnackBar
  other,
}

/// [PaneWriter] 経由の mutation 呼び出しを try-catch でラップする際の分類器。
class HerdrMutationErrorClassifier {
  const HerdrMutationErrorClassifier();

  HerdrMutationClass classify(Object e) {
    if (isHerdrTargetNotFound(e)) return HerdrMutationClass.targetNotFound;
    if (isHerdrInvalidKey(e)) return HerdrMutationClass.invalidKey;
    if (e is PaneOperationNoopException) return HerdrMutationClass.noop;
    if (isServerDownException(e)) return HerdrMutationClass.serverDown;
    if (e is SshConnectionError) return HerdrMutationClass.sshDisconnected;
    return HerdrMutationClass.other;
  }
}
