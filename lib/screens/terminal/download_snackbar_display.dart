import 'package:flutter/material.dart';

import '../../providers/download_provider.dart';
import '../../theme/design_colors.dart';
import '../../l10n/app_localizations.dart';

/// ダウンロード転送の SnackBar 表示仕様（T12）。
///
/// 文言・色を [downloadSnackBarDisplay] から導出し、表示遷移（ScaffoldMessenger）
/// は session 側のリスナーが行う。仕様を純関数化することで、TerminalScreen 全体を
/// pump せずに phase 遷移ごとの表示をテストできる。
class DownloadSnackBarDisplay {
  const DownloadSnackBarDisplay({required this.message, this.backgroundColor});

  final String message;
  final Color? backgroundColor;
}

/// downloadProvider の phase 遷移に対する SnackBar 仕様を導出する。
///
/// - **phase 遷移時のみ**仕様を返し、進捗 publish・idle 復帰では null（発火しない）。
/// - completed（全成功）: 緑 + 完了文言（「開く」アクションは廃止）
/// - completed（部分失敗）: 赤 + 集約（T16 補完）
/// - completed（全スキップ）: 集約表示（中立色・LOW#3）
/// - cancelled: 中立（既定色）
/// - error: 赤 + エラー文言 + 集約
DownloadSnackBarDisplay? downloadSnackBarDisplay(
  AppLocalizations l10n,
  DownloadState state,
  DownloadPhase? previousPhase,
) {
  if (previousPhase == state.phase) return null;
  final summary = l10n.fileDownloadResultSummary(
    state.completedCount,
    state.failedCount,
    state.skippedCount,
  );
  switch (state.phase) {
    case DownloadPhase.completed:
      if (state.errorMessage != null) {
        // 部分失敗: 赤 + 集約報告（「開く」アクションは廃止）。
        return DownloadSnackBarDisplay(
          message: '${l10n.fileDownloadError}（$summary）',
          backgroundColor: DesignColors.error,
        );
      }
      // 全スキップ（成功 0・失敗 0・スキップのみ）: 緑の「Download complete」は誤認誘発
      // → 集約表示（fileDownloadResultSummary・中立色）。review LOW#3 対応。
      if (state.completedCount == 0 &&
          state.skippedCount > 0 &&
          state.failedCount == 0) {
        return DownloadSnackBarDisplay(message: summary);
      }
      // 全成功（成功 + スキップ混在を含む）: 緑 + 完了文言。
      return DownloadSnackBarDisplay(
        message: l10n.fileDownloadComplete,
        backgroundColor: DesignColors.success,
      );
    case DownloadPhase.cancelled:
      return DownloadSnackBarDisplay(message: l10n.fileDownloadCancelled);
    case DownloadPhase.error:
      return DownloadSnackBarDisplay(
        message: '${l10n.fileDownloadError}（$summary）',
        backgroundColor: DesignColors.error,
      );
    default:
      return null;
  }
}
