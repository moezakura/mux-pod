import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/l10n_lookup.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

/// ダウンロード集約 SnackBar（T16）の Unit テスト。
///
/// 検証対象（実装計画 §L2-2 SnackBar / Phase 6 #16）:
/// - 一括集約（成功 a / 失敗 b / スキップ c・fileDownloadResultSummary）が
///   複数アイテムでも正しく動作すること
/// - 部分失敗時は赤 + 集約報告（「開く」アクションは廃止）
/// - 全スキップ（LOW#3）: 緑の「Download complete」でなく集約表示（中立色）
DownloadItemState _item(
  String name, {
  bool isCompleted = false,
  bool isError = false,
  bool isSkipped = false,
}) {
  return DownloadItemState(
    remotePath: '/remote/$name',
    name: name,
    localPath: '/tmp/dl/$name',
    totalBytes: 300,
    bytesReceived: isCompleted ? 300 : 0,
    isCompleted: isCompleted,
    isError: isError,
    isSkipped: isSkipped,
    errorMessage: isError ? 'boom' : null,
  );
}

void main() {
  final en = l10nForLanguage('en');

  group('downloadSnackBarDisplay（T16・複数アイテムの一括集約）', () {
    test('複数 3 件全成功: 緑 + 完了文言（「開く」アクションは廃止）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [
          _item('a.bin', isCompleted: true),
          _item('b.bin', isCompleted: true),
          _item('c.bin', isCompleted: true),
        ],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(display!.message, 'Download complete');
      expect(display.backgroundColor, DesignColors.success);
    });

    test('部分失敗（成功1/失敗1/スキップ1）: 赤 + 集約（「開く」アクションは廃止）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        errorMessage: 'Download failed',
        items: [
          _item('a.bin', isCompleted: true),
          _item('b.bin', isError: true),
          _item('c.bin', isSkipped: true),
        ],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(
        display!.message,
        'Download failed（1 succeeded, 1 failed, 1 skipped）',
      );
      expect(display.backgroundColor, DesignColors.error);
    });

    test('部分失敗で成功 0（失敗 2）: 赤 + 集約', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        errorMessage: 'Download failed',
        items: [_item('a.bin', isError: true), _item('b.bin', isError: true)],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(
        display!.message,
        'Download failed（0 succeeded, 2 failed, 0 skipped）',
      );
      expect(display.backgroundColor, DesignColors.error);
    });

    test('全スキップ（成功0/失敗0/スキップのみ）: 集約表示・中立色（LOW#3）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [
          _item('a.bin', isSkipped: true),
          _item('b.bin', isSkipped: true),
        ],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      // 緑の「Download complete」ではなく集約表示（成功 0 / 失敗 0 / スキップ 2）。
      expect(display!.message, '0 succeeded, 0 failed, 2 skipped');
      expect(display.backgroundColor, isNull); // 中立色
    });

    test('成功 + スキップ混在（成功あり）: 緑 + 完了文言', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [
          _item('a.bin', isCompleted: true),
          _item('c.bin', isSkipped: true),
        ],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(display!.message, 'Download complete');
      expect(display.backgroundColor, DesignColors.success);
    });

    test('error（複数・失敗2/スキップ1）: 赤 + 集約', () {
      final state = DownloadState(
        phase: DownloadPhase.error,
        errorMessage: 'Download failed',
        items: [
          _item('a.bin', isError: true),
          _item('b.bin', isError: true),
          _item('c.bin', isSkipped: true),
        ],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(
        display!.message,
        'Download failed（0 succeeded, 2 failed, 1 skipped）',
      );
      expect(display.backgroundColor, DesignColors.error);
    });

    test('cancelled（複数）: 中立', () {
      final state = DownloadState(
        phase: DownloadPhase.cancelled,
        items: [_item('a.bin'), _item('b.bin', isCompleted: true)],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(display!.message, 'Download cancelled');
      expect(display.backgroundColor, isNull);
    });
  });
}