import 'dart:io' show Platform;

import 'package:saf_util/saf_util.dart';

import 'download_destination.dart';
import 'ios_scoped_folder.dart';
import 'saf_destination.dart';

/// バッチダウンロードの保存先ディレクトリを選ぶピッカーの抽象。
abstract class BatchDestinationPicker {
  /// ユーザーに保存先フォルダを選択させ、対応する [DownloadDestination] を返す。
  ///
  /// - キャンセル時は `null` を返す。
  /// - 未対応プラットフォーム（デスクトップ等）は `null` を返す。
  /// - 例外（選択失敗等）はそのまま伝播する（呼び出し側でエラー報告する）。
  Future<DownloadDestination?> pick();
}

/// 実行時プラットフォームに応じて保存先を選択する [BatchDestinationPicker]。
///
/// - Android: [SafUtil.pickDirectory]（writePermission 付き）→ [SafDirectoryDestination]。
/// - iOS: セキュリティスコープ付きフォルダ選択 → [IosScopedDirectoryDestination.prepare]。
/// - その他（デスクトップ等）: 現状未対応のため `null`。
///
/// テスト注入: [isAndroidOverride] / [isIOSOverride]（null なら [Platform] で実環境判定。
/// プラットフォーム判定を差し替えて各分岐を検証するための前例に倣う）。
class PlatformBatchDestinationPicker implements BatchDestinationPicker {
  const PlatformBatchDestinationPicker({
    this.isAndroidOverride,
    this.isIOSOverride,
  });

  /// テスト注入用の Android 判定（null なら `Platform.isAndroid`）。
  final bool? isAndroidOverride;

  /// テスト注入用の iOS 判定（null なら `Platform.isIOS`）。
  final bool? isIOSOverride;

  bool get _isAndroid => isAndroidOverride ?? Platform.isAndroid;
  bool get _isIOS => isIOSOverride ?? Platform.isIOS;

  @override
  Future<DownloadDestination?> pick() async {
    if (_isAndroid) {
      final dir = await SafUtil().pickDirectory(writePermission: true);
      if (dir == null) return null; // キャンセル。
      return SafDirectoryDestination(dir.uri);
    }
    if (_isIOS) {
      final bookmark = await const IosScopedFolder().pickFolder();
      if (bookmark == null) return null; // キャンセル。
      return IosScopedDirectoryDestination.prepare(bookmark: bookmark);
    }
    return null; // 未対応プラットフォーム。
  }
}
