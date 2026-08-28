import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/l10n_lookup.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

/// ダウンロード転送の SnackBar 報告仕様（T12）のユニットテスト。
///
/// 検証対象（実装計画 §L2-2 SnackBar / Phase 4 #12）:
/// - **phase 遷移時のみ**仕様を返す（進捗 publish・idle 復帰では発火しない）
/// - completed（全成功）: 緑 + 完了文言（「開く」アクションは廃止）
/// - completed（部分失敗）: 赤 + 集約（成功 a / 失敗 b / スキップ c）
/// - cancelled: 中立（既定色）
/// - error: 赤 + エラー文言 + 集約
///
/// 表示遷移（ScaffoldMessenger）は terminal_screen の _ensureDownloadListener が担い、
/// 本テストは仕様ロジック（純関数）を検証する（TerminalScreen 全体の pump による
/// google_fonts / connectivity 等の副作用を回避）。
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

  group('downloadSnackBarDisplay（T12・phase 遷移時のみ発火）', () {
    test('phase 遷移なし（進捗 publish）では null', () {
      final state = DownloadState(
        phase: DownloadPhase.downloading,
        items: [_item('a.bin')],
      );
      // 同一 phase（進捗更新）では発火しない
      expect(
        downloadSnackBarDisplay(en, state, DownloadPhase.downloading),
        isNull,
      );
    });

    test(
      'idle / selecting / downloading / awaitingOverwrite からの遷移先が無ければ null',
      () {
        final idle = const DownloadState(phase: DownloadPhase.idle);
        expect(
          downloadSnackBarDisplay(en, idle, DownloadPhase.completed),
          isNull,
        );
        expect(
          downloadSnackBarDisplay(
            en,
            const DownloadState(phase: DownloadPhase.selecting),
            DownloadPhase.idle,
          ),
          isNull,
        );
      },
    );

    test('completed（全成功）: 緑 + 完了文言（「開く」アクションは廃止）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [_item('a.bin', isCompleted: true)],
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

    test('completed（部分失敗）: 赤 + 集約（成功a/失敗b/スキップc）', () {
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

    test('cancelled: 中立（既定色）・キャンセル文言', () {
      final state = DownloadState(
        phase: DownloadPhase.cancelled,
        items: [_item('a.bin')],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(display!.message, 'Download cancelled');
      expect(display.backgroundColor, isNull); // 中立
    });

    test('error: 赤 + エラー文言 + 集約', () {
      final state = DownloadState(
        phase: DownloadPhase.error,
        errorMessage: 'Download failed',
        items: [_item('a.bin', isError: true), _item('b.bin', isSkipped: true)],
      );
      final display = downloadSnackBarDisplay(
        en,
        state,
        DownloadPhase.downloading,
      );

      expect(display, isNotNull);
      expect(
        display!.message,
        'Download failed（0 succeeded, 1 failed, 1 skipped）',
      );
      expect(display.backgroundColor, DesignColors.error);
    });
  });
}
