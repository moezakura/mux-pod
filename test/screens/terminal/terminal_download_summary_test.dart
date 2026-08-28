import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/l10n_lookup.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

/// ダウンロード集約 SnackBar（T16）と共有対象の抽出（T14）の Unit テスト。
///
/// 検証対象（実装計画 §L2-2 SnackBar / Phase 6 #16 + Phase 5 #14）:
/// - 一括集約（成功 a / 失敗 b / スキップ c・fileDownloadResultSummary）が
///   複数アイテムでも正しく動作すること
/// - 部分失敗時は「開く」が成功ファイルのみ対象（T16 仕様補完・L1-a）
/// - 全スキップ（LOW#3）: 緑の「Download complete」でなく集約表示（中立色・開くなし）
/// - [successfulDownloadLocalPaths]: 共有/「開く」対象＝成功ファイルのみ
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

  group('successfulDownloadLocalPaths（T14・「開く」は成功ファイルのみ）', () {
    test('成功のみ抽出（失敗・スキップを除外）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [
          _item('a.bin', isCompleted: true),
          _item('b.bin', isError: true),
          _item('c.bin', isSkipped: true),
          _item('d.bin', isCompleted: true),
        ],
      );

      expect(successfulDownloadLocalPaths(state), [
        '/tmp/dl/a.bin',
        '/tmp/dl/d.bin',
      ]);
    });

    test('全失敗/全スキップ → 空（共有しない）', () {
      final failed = DownloadState(
        phase: DownloadPhase.completed,
        items: [_item('a.bin', isError: true), _item('b.bin', isError: true)],
      );
      expect(successfulDownloadLocalPaths(failed), isEmpty);

      final skipped = DownloadState(
        phase: DownloadPhase.completed,
        items: [_item('a.bin', isSkipped: true)],
      );
      expect(successfulDownloadLocalPaths(skipped), isEmpty);
    });

    test('空 items → 空', () {
      const state = DownloadState(phase: DownloadPhase.completed);
      expect(successfulDownloadLocalPaths(state), isEmpty);
    });
  });

  group('downloadSnackBarDisplay（T16・複数アイテムの一括集約）', () {
    test('複数 3 件全成功: 緑 + 「開く」', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [
          _item('a.bin', isCompleted: true),
          _item('b.bin', isCompleted: true),
          _item('c.bin', isCompleted: true),
        ],
      );
      final display = downloadSnackBarDisplay(en, state, DownloadPhase.downloading);

      expect(display, isNotNull);
      expect(display!.message, 'Download complete');
      expect(display.backgroundColor, DesignColors.success);
      expect(display.actionLabel, 'Open');
    });

    test('部分失敗（成功1/失敗1/スキップ1）: 赤 + 集約 + 「開く」（成功分のみ・T16 補完）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        errorMessage: 'Download failed',
        items: [
          _item('a.bin', isCompleted: true),
          _item('b.bin', isError: true),
          _item('c.bin', isSkipped: true),
        ],
      );
      final display = downloadSnackBarDisplay(en, state, DownloadPhase.downloading);

      expect(display, isNotNull);
      expect(display!.message, 'Download failed（1 succeeded, 1 failed, 1 skipped）');
      expect(display.backgroundColor, DesignColors.error);
      // T16 補完: 部分失敗でも成功ファイルがあれば「開く」（共有は成功分のみ）。
      expect(display.actionLabel, 'Open');
    });

    test('部分失敗で成功 0（失敗 2）: 赤 + 集約・「開く」なし（成功分が無いため）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        errorMessage: 'Download failed',
        items: [_item('a.bin', isError: true), _item('b.bin', isError: true)],
      );
      final display = downloadSnackBarDisplay(en, state, DownloadPhase.downloading);

      expect(display, isNotNull);
      expect(display!.message, 'Download failed（0 succeeded, 2 failed, 0 skipped）');
      expect(display.backgroundColor, DesignColors.error);
      expect(display.actionLabel, isNull);
    });

    test('全スキップ（成功0/失敗0/スキップのみ）: 集約表示・中立色・「開く」なし（LOW#3）', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [_item('a.bin', isSkipped: true), _item('b.bin', isSkipped: true)],
      );
      final display = downloadSnackBarDisplay(en, state, DownloadPhase.downloading);

      expect(display, isNotNull);
      // 緑の「Download complete」ではなく集約表示（成功 0 / 失敗 0 / スキップ 2）。
      expect(display!.message, '0 succeeded, 0 failed, 2 skipped');
      expect(display.backgroundColor, isNull); // 中立色
      expect(display.actionLabel, isNull);
    });

    test('成功 + スキップ混在（成功あり）: 緑 + 「開く」＝既存仕様を維持', () {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [
          _item('a.bin', isCompleted: true),
          _item('c.bin', isSkipped: true),
        ],
      );
      final display = downloadSnackBarDisplay(en, state, DownloadPhase.downloading);

      expect(display, isNotNull);
      expect(display!.message, 'Download complete');
      expect(display.backgroundColor, DesignColors.success);
      expect(display.actionLabel, 'Open');
    });

    test('error（複数・失敗2/スキップ1）: 赤 + 集約・「開く」なし', () {
      final state = DownloadState(
        phase: DownloadPhase.error,
        errorMessage: 'Download failed',
        items: [
          _item('a.bin', isError: true),
          _item('b.bin', isError: true),
          _item('c.bin', isSkipped: true),
        ],
      );
      final display = downloadSnackBarDisplay(en, state, DownloadPhase.downloading);

      expect(display, isNotNull);
      expect(display!.message, 'Download failed（0 succeeded, 2 failed, 1 skipped）');
      expect(display.backgroundColor, DesignColors.error);
      expect(display.actionLabel, isNull);
    });

    test('cancelled（複数）: 中立・「開く」なし', () {
      final state = DownloadState(
        phase: DownloadPhase.cancelled,
        items: [_item('a.bin'), _item('b.bin', isCompleted: true)],
      );
      final display = downloadSnackBarDisplay(en, state, DownloadPhase.downloading);

      expect(display, isNotNull);
      expect(display!.message, 'Download cancelled');
      expect(display.backgroundColor, isNull);
      expect(display.actionLabel, isNull);
    });
  });
}