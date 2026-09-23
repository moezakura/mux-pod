// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/batch_destination_picker_provider.dart';
import '../../providers/download_provider.dart';
import '../../services/sftp/file_entry.dart';
import '../../services/sftp/overwrite_choice.dart';
import '../../widgets/dialogs/overwrite_confirm_dialog.dart';
import 'widgets/transfer_progress_sheet.dart';

/// ダウンロード位相の協調オブジェクト（T10/T11）。
///
/// [downloadProvider] のフェーズ遷移リスナー（[attach]）と進捗シートの
/// 多重表示防止フラグ（`_sheetOpen`）を単一所有する。`BuildContext` は
/// **保持しない**。context 依存メソッドは呼び出し元（root State）から
/// メソッド引数で都度受ける。
class FileBrowserDownloadFlow {
  FileBrowserDownloadFlow();

  late WidgetRef _ref;
  ProviderSubscription<DownloadState>? _sub;

  /// 進捗シートの多重表示防止（already-mounted エラー回避）。
  bool _sheetOpen = false;

  /// フェーズ遷移リスナーを登録する（root の initState で呼ぶ）。
  ///
  /// [onPhaseChanged] は位相遷移時のみ呼ばれる（進捗 publish では発火しない）。
  void attach(
    WidgetRef ref, {
    required void Function(DownloadPhase phase) onPhaseChanged,
  }) {
    _sub?.close();
    _ref = ref;
    _sub = ref.listenManual<DownloadState>(downloadProvider, (prev, next) {
      if (prev?.phase == next.phase) return;
      onPhaseChanged(next.phase);
    });
  }

  /// リスナー購読を解除する（root の dispose で呼ぶ）。
  void dispose() {
    _sub?.close();
    _sub = null;
    _sheetOpen = false;
  }

  /// 一括ダウンロード（T15）: 選択一覧を保存先選択（1 回）→ startDownloads →
  /// 順次転送。awaitingOverwrite → 上書き確認 / downloading → 進捗シートは
  /// [attach] のフェーズリスナーが担当する（既存 T10/T11 導線の再利用）。
  Future<void> startBatch(List<FileEntry> entries, BuildContext context) async {
    if (entries.isEmpty) return;
    final dest = await _ref.read(batchDestinationPickerProvider).pick();
    if (dest == null || !context.mounted) return; // 保存先キャンセル → idle 維持
    await _ref.read(downloadProvider.notifier).startDownloads(entries, dest);
  }

  /// 単一ダウンロード: Tmp ダウンロード → exporting（OS Save-As）→ completed/cancelled。
  /// 保存先選択は OS ダイアログ側（基盤 SaveAsExporter）が担うため直接呼び出す。
  Future<void> startSingle(FileEntry entry) async {
    await _ref.read(downloadProvider.notifier).startSingleTmpDownload(entry);
  }

  /// awaitingOverwrite: 同名衝突の事前スキャン検出を基盤ダイアログで一括確認（🤝#5）。
  Future<void> handleAwaitingOverwrite(BuildContext context) async {
    final decisions = await collectOverwriteDecisions(context);
    if (!context.mounted) return;
    if (decisions == null) {
      // null 戻り値（barrier/back dismiss）= 操作中断 → バッチ中断（転送開始しない）。
      _ref.read(downloadProvider.notifier).reset();
      return;
    }
    await _ref
        .read(downloadProvider.notifier)
        .applyOverwriteDecisions(decisions);
  }

  /// downloading: 進捗シートを表示（多重表示防止・閉じても転送は継続）。
  void showProgressSheet(BuildContext context) {
    if (_sheetOpen) return;
    _sheetOpen = true;
    showTransferProgressSheet(context).whenComplete(() {
      _sheetOpen = false;
    });
  }

  /// 上書き確認導線。[DownloadState.collidingItems] をファイルごとに
  /// 基盤 [showOverwriteConfirmDialog]（batch モード + 全ファイル適用）で確認する。
  ///
  /// - null 戻り値（barrier/back dismiss）＝操作中断 → 呼び出し側でバッチ中断（reset）。
  /// - `applyToAll == true` は残り全衝突へ同じ決定を適用する（基盤契約 C-8）。
  /// - 決定は `Map<name, OverwriteChoice>` で返し、呼び出し側が applyOverwriteDecisions へ渡す。
  Future<Map<String, OverwriteChoice>?> collectOverwriteDecisions(
    BuildContext context,
  ) async {
    final decisions = <String, OverwriteChoice>{};
    final remaining = List.of(_ref.read(downloadProvider).collidingItems);
    while (remaining.isNotEmpty) {
      final item = remaining.removeAt(0);
      final result = await showOverwriteConfirmDialog(
        context,
        fileName: item.name,
        mode: OverwriteDialogMode.batch,
        showApplyToAll: true,
      );
      if (result == null) return null; // 操作中断 → バッチ中断
      decisions[item.name] = result.choice;
      if (result.applyToAll) {
        for (final rest in remaining) {
          decisions[rest.name] = result.choice;
        }
        break;
      }
    }
    return decisions;
  }
}
