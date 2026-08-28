import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// ダウンロード済みファイルの共有（受入⑦・share_plus）。
///
/// - `Platform.isAndroid` ガード: 未対応プラットフォームは「保存のみ」にフォールバック
///   （共有シートを出さない）。
/// - 失敗（throw）は catch して「保存のみ」にフォールバック（転送結果・SnackBar に
///   影響させない・再 throw しない）。
/// - 空リストは no-op（共有対象なし）。
///
/// 共有対象（成功ファイルのみ）の選別は呼び出し側（terminal_screen の
/// [successfulDownloadLocalPaths]）が行い、本サービスは「渡されたパスの共有実行」のみ
/// を責務とする。テスト注入: [isAndroidOverride]（null なら実環境判定）/
/// [shareOverride]（null なら SharePlus.instance.share）は DownloadNotifier の
/// clock / notificationService 注入前例に倣う（テスト二重なしではプラグイン呼び出しの
/// ガード・フォールバックを検証できないため）。
class DownloadShareService {
  const DownloadShareService({
    this.isAndroidOverride,
    this.shareOverride,
  });

  /// テスト注入用の Android 判定（null なら `Platform.isAndroid`）。
  final bool? isAndroidOverride;

  /// テスト注入用の共有実行（null なら `SharePlus.instance.share`）。
  final Future<void> Function(List<String> localPaths)? shareOverride;

  /// ダウンロード済みファイルを共有シートで開く/送る。
  ///
  /// 呼び出し規約: ①引数 [localPaths]（空許容→no-op・null なし）②失敗時 throw しない
  /// （catch で保存のみフォールバック）③async ④副作用=OS 共有シート表示（Android のみ）。
  Future<void> shareFiles(List<String> localPaths) async {
    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    if (!isAndroid || localPaths.isEmpty) return; // 未対応 PF・対象なし: 保存のみ

    try {
      final share = shareOverride;
      if (share != null) {
        await share(localPaths);
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [for (final path in localPaths) XFile(path)]),
      );
    } catch (e) {
      // 共有失敗: 「保存のみ」にフォールバック（throw は catch・転送結果は不変）。
      debugPrint('DownloadShare: share failed (files saved only): $e');
    }
  }
}