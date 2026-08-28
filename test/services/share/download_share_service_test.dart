import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/share/download_share_service.dart';

/// ダウンロード済みファイル共有（T14・受入⑦）の Unit テスト。
///
/// 検証対象（実装計画 §L2-4 外部API #1 / Phase 5 #14）:
/// - `Platform.isAndroid` ガード: 未対応プラットフォームは共有しない（保存のみ）
/// - 空リストは no-op（共有対象なし）
/// - Android では渡されたパスがそのまま共有実行に渡る（成功ファイルのみ＝呼び出し側が選別）
/// - 共有失敗（throw）は catch して保存のみにフォールバック（再 throw しない）
///
/// プラグイン実呼び出しは [DownloadShareService.shareOverride] で注入し、
/// ガード・フォールバックの分岐を検証する（DownloadNotifier の clock /
/// notificationService 注入前例に倣う）。
void main() {
  group('DownloadShareService.shareFiles（T14）', () {
    test('未対応プラットフォーム（isAndroid=false）では共有を実行しない（保存のみ）', () async {
      final shared = <List<String>>[];
      final service = DownloadShareService(
        isAndroidOverride: false,
        shareOverride: (paths) async => shared.add(paths),
      );

      await service.shareFiles(['/tmp/dl/a.bin']);

      expect(shared, isEmpty);
    });

    test('空リストは no-op（共有対象なし・プラグインも呼ばれない）', () async {
      final shared = <List<String>>[];
      final service = DownloadShareService(
        isAndroidOverride: true,
        shareOverride: (paths) async => shared.add(paths),
      );

      await service.shareFiles([]);

      expect(shared, isEmpty);
    });

    test('Android では共有対象パスがそのまま共有実行に渡る', () async {
      final shared = <List<String>>[];
      final service = DownloadShareService(
        isAndroidOverride: true,
        shareOverride: (paths) async => shared.add(paths),
      );

      await service.shareFiles(['/tmp/dl/a.bin', '/tmp/dl/b.bin']);

      expect(shared, [
        ['/tmp/dl/a.bin', '/tmp/dl/b.bin'],
      ]);
    });

    test('共有失敗（throw）は保存のみにフォールバック（再 throw しない）', () async {
      final service = DownloadShareService(
        isAndroidOverride: true,
        shareOverride: (_) async => throw Exception('share sheet unavailable'),
      );

      // 例外が伝播せず、保存のみのフォールバックとして完了する。
      await service.shareFiles(['/tmp/dl/a.bin']);
    });
  });
}