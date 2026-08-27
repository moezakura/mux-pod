import 'package:flutter/material.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/services/sftp/transfer_format.dart';
import 'package:flutter_muxpod/services/sftp/transfer_progress.dart';
import 'package:flutter_muxpod/widgets/file_transfer/transfer_progress_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferProgress', () {
    test('fraction: totalBytes>0 で 0-1 を返す', () {
      const p = TransferProgress(doneBytes: 500, totalBytes: 1000);
      expect(p.fraction, closeTo(0.5, 0.0001));
    });

    test('fraction: totalBytes=0（サイズ未知）なら null', () {
      const p = TransferProgress(doneBytes: 500, totalBytes: 0);
      expect(p.fraction, isNull);
    });

    test('percent: fraction から 0-100 を丸める', () {
      const p = TransferProgress(doneBytes: 500, totalBytes: 1000);
      expect(p.percent, 50);
    });

    test('percent: サイズ未知なら null', () {
      const p = TransferProgress(doneBytes: 500, totalBytes: 0);
      expect(p.percent, isNull);
    });

    test('copyWith は指定フィールドのみ上書き', () {
      const p = TransferProgress(
        doneBytes: 1,
        totalBytes: 10,
        bytesPerSec: 2.0,
      );
      final p2 = p.copyWith(doneBytes: 5);
      expect(p2.doneBytes, 5);
      expect(p2.totalBytes, 10);
      expect(p2.bytesPerSec, 2.0);
    });

    test('fromBytes は累積バイトから生成（進捗管理の基本）', () {
      final p = TransferProgress.fromBytes(300, totalBytes: 600);
      expect(p.doneBytes, 300);
      expect(p.totalBytes, 600);
      expect(p.fraction, closeTo(0.5, 0.0001));
    });

    test('fromFraction は UI 表示用に fraction を概ね再現', () {
      final p = TransferProgress.fromFraction(0.25);
      expect(p.fraction, closeTo(0.25, 0.001));
      expect(p.percent, 25);
    });
  });

  group('TransferSpeedEma', () {
    test('初回 update は 0 を返す', () {
      final ema = TransferSpeedEma();
      expect(ema.update(1024), 0);
    });

    test('定数レート（clock 注入）で期待速度になる', () {
      // t0: 初回（0 返却）→ t1: +1024B / 1s → t2: +1024B / 1s
      final times = <DateTime>[
        DateTime(2024, 1, 1, 0, 0, 0),
        DateTime(2024, 1, 1, 0, 0, 1),
        DateTime(2024, 1, 1, 0, 0, 2),
      ];
      var i = 0;
      final ema = TransferSpeedEma(clock: () => times[i]);
      expect(ema.update(0, now: times[i++]), 0); // 初回
      // t1: instant = 1024/1 = 1024（_speed==0 → instant 採用）
      expect(ema.update(1024, now: times[i++]), closeTo(1024, 0.0001));
      // t2: EMA = 0.3*1024 + 0.7*1024 = 1024（定数レートでは EMA も 1024 に収束）
      expect(ema.update(2048, now: times[i++]), closeTo(1024, 0.0001));
    });

    test('reset で状態がクリアされ次回は 0 を返す', () {
      final times = <DateTime>[
        DateTime(2024, 1, 1, 0, 0, 0),
        DateTime(2024, 1, 1, 0, 0, 1),
        DateTime(2024, 1, 1, 0, 0, 2),
      ];
      var i = 0;
      final ema = TransferSpeedEma(clock: () => times[i]);
      ema.update(0, now: times[i++]);
      ema.update(1024, now: times[i++]);
      ema.reset();
      expect(ema.update(2048, now: times[i++]), 0); // reset 後の初回は 0
    });
  });

  group('formatTransferSpeed', () {
    test('B/s・KB/s・MB/s・GB/s の 4 段階', () {
      expect(formatTransferSpeed(500), '500.0 B/s');
      expect(formatTransferSpeed(1024), '1.0 KB/s');
      expect(formatTransferSpeed(2 * 1024 * 1024), '2.0 MB/s');
      expect(formatTransferSpeed(3 * 1024 * 1024 * 1024), '3.0 GB/s');
    });
  });

  group('TransferProgressRow', () {
    Future<void> pumpRow(
      WidgetTester tester, {
      required TransferProgress progress,
      String? label,
      VoidCallback? onCancel,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TransferProgressRow(
              progress: progress,
              label: label,
              onCancel: onCancel,
            ),
          ),
        ),
      );
    }

    testWidgets('fraction ありは determinate 表示・キャンセル null で非表示', (tester) async {
      await pumpRow(
        tester,
        progress: const TransferProgress(
          doneBytes: 512,
          totalBytes: 1024,
          bytesPerSec: 1024,
        ),
        label: 'file.txt',
      );
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(0.5, 0.0001));
      // キャンセルボタンは onCancel null なので非表示
      expect(find.byIcon(Icons.close), findsNothing);
      // label 表示
      expect(find.text('file.txt'), findsOneWidget);
    });

    testWidgets('fraction null（サイズ未知）は不定表示・キャンセル表示', (tester) async {
      var cancelled = false;
      await pumpRow(
        tester,
        progress: const TransferProgress(doneBytes: 100, totalBytes: 0),
        onCancel: () => cancelled = true,
      );
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, isNull); // 不定表示
      final cancelButton = find.byIcon(Icons.close);
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      expect(cancelled, isTrue);
    });
  });
}
