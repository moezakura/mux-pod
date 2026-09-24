// P4 回帰テスト（パリティ・ダウンロード SnackBar）: phase 遷移でない進捗
// publish では空の SnackBar が出ないこと（NG-1）を固定する。
//
// P4 リファクタ前に `null → DownloadDisplaySpec(message: '', ...)` の sentinel
// 置換で「進捗 publish のたびに空の floating SnackBar」が表示されていた。
// 修正後は純関数の null がそのまま伝搬し、transfer flow の
// `if (display == null) return;` が機能する。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';

import '../../helpers/terminal_parity_pump.dart';

DownloadItemState _item(String name, {bool completed = false}) {
  return DownloadItemState(
    remotePath: '/remote/$name',
    name: name,
    localPath: '/tmp/dl/$name',
    totalBytes: 300,
    bytesReceived: completed ? 300 : 100,
    isCompleted: completed,
  );
}

void main() {
  group('P4 parity: ダウンロード進捗 publish（NG-1）', () {
    testWidgets('phase 遷移のない進捗 publish では空の SnackBar を出さない', (tester) async {
      await TerminalParityPump.pumpTerminalScreen(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      // ignore: avoid_dynamic_calls
      final download = container.read(downloadProvider.notifier) as dynamic;

      // 1) 進捗 publish（downloading → downloading・同一 phase・items 更新）
      download.emit(
        DownloadState(
          phase: DownloadPhase.downloading,
          items: [_item('a.bin')],
        ),
      );
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);

      // 2) もう一度進捗 publish（さらに items を更新）→ 依然空 SnackBar なし
      download.emit(
        DownloadState(
          phase: DownloadPhase.downloading,
          items: [_item('a.bin', completed: true), _item('b.bin')],
        ),
      );
      await tester.pump();
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'phase 遷移なし（進捗のみ）では SnackBar を表示しない',
      );
    });

    testWidgets('phase 遷移（completed）では正常に SnackBar を表示する', (tester) async {
      await TerminalParityPump.pumpTerminalScreen(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );
      // ignore: avoid_dynamic_calls
      final download = container.read(downloadProvider.notifier) as dynamic;

      download.emit(
        DownloadState(
          phase: DownloadPhase.downloading,
          items: [_item('a.bin')],
        ),
      );
      await tester.pump();

      // completed（全成功）へ phase 遷移 → 完了 SnackBar が出る（リスナーが生きている証明）
      download.emit(
        DownloadState(
          phase: DownloadPhase.completed,
          items: [_item('a.bin', completed: true)],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byType(SnackBar),
        findsOneWidget,
        reason: 'phase 遷移時のみ SnackBar を表示する',
      );
    });
  });
}
