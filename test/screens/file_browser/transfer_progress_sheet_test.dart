import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/download_provider.dart';
import 'package:flutter_muxpod/screens/file_browser/widgets/transfer_progress_sheet.dart';
import 'package:flutter_muxpod/widgets/file_transfer/transfer_progress_row.dart';

/// displayProvider を固定状態にするフェイク。
///
/// シートの UI 検証は実転送（実 IO）なしで行う。`cancel()` は親実装が phase を
/// cancelled に遷移させる（token は未生成のため no-op）。
class _FakeDownloadNotifier extends DownloadNotifier {
  _FakeDownloadNotifier(this.initial);

  final DownloadState initial;

  @override
  DownloadState build() => initial;
}

DownloadItemState _item(
  String name, {
  int totalBytes = 300,
  int received = 0,
  bool isError = false,
  bool isSkipped = false,
  bool isCompleted = false,
  String? errorMessage,
}) {
  return DownloadItemState(
    remotePath: '/remote/$name',
    name: name,
    localPath: '/tmp/dl/$name',
    totalBytes: totalBytes,
    bytesReceived: received,
    isError: isError,
    isSkipped: isSkipped,
    isCompleted: isCompleted,
    errorMessage: errorMessage,
  );
}

Future<ProviderContainer> pumpSheet(
  WidgetTester tester,
  DownloadState state,
) async {
  final container = ProviderContainer(
    overrides: [
      downloadProvider.overrideWith(() => _FakeDownloadNotifier(state)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showTransferProgressSheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('showTransferProgressSheet', () {
    testWidgets('downloading 中に全体進捗・件数・速度・アイテム行を表示する', (tester) async {
      final state = DownloadState(
        phase: DownloadPhase.downloading,
        items: [
          _item('a.bin', received: 100),
          _item('b.bin', received: 300, isCompleted: true),
          _item('c.bin', isError: true, errorMessage: 'boom'),
          _item('d.bin', isSkipped: true),
        ],
        speedLabel: '1.5 MB/s',
      );
      final container = await pumpSheet(tester, state);

      // 全アイテム行（基盤 TransferProgressRow を使用）
      expect(find.byType(TransferProgressRow), findsNWidgets(4));
      // 処理済み n / 全件（completed 1 + failed 1 + skipped 1 = 3 / 4）
      expect(find.text('3 / 4'), findsOneWidget);
      // 全体速度
      expect(find.text('1.5 MB/s'), findsOneWidget);
      // エラー赤字の理由表示
      expect(find.text('boom'), findsOneWidget);
      expect(find.text('c.bin'), findsOneWidget);
      // スキップ表記
      expect(find.text('d.bin（Skip）'), findsOneWidget);
      expect(container.read(downloadProvider).phase, DownloadPhase.downloading);
    });

    testWidgets('キャンセルボタンで phase=cancelled になりシートが閉じる', (tester) async {
      final state = DownloadState(
        phase: DownloadPhase.downloading,
        items: [_item('a.bin', received: 50)],
        speedLabel: '0 B/s',
      );
      final container = await pumpSheet(tester, state);

      expect(find.byType(TransferProgressRow), findsOneWidget);

      await tester.tap(find.text('Cancel transfer'));
      await tester.pumpAndSettle();

      expect(container.read(downloadProvider).phase, DownloadPhase.cancelled);
      // シートは自動クローズされる
      expect(find.byType(TransferProgressRow), findsNothing);
    });

    testWidgets('completed フェーズではシートは自動クローズされる', (tester) async {
      final state = DownloadState(
        phase: DownloadPhase.completed,
        items: [_item('a.bin', received: 300, isCompleted: true)],
      );
      await pumpSheet(tester, state);

      // after pump 直後は表示され、自動クローズされる（post-frame の pop 後）
      await tester.pumpAndSettle();
      expect(find.byType(TransferProgressRow), findsNothing);
    });
  });
}