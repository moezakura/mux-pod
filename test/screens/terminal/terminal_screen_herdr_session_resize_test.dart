import 'package:flutter_test/flutter_test.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('タスク①: herdr ターミナル全体 resize（Select Session）', () {
    testWidgets('セッションセレクタの Resize で PTY 要求サイズ変更が成功すると hidden TUI 経由で同期される', (
      tester,
    ) async {
      final client = await pumpHerdrAndOpenWorkspaceSelector(
        tester,
        clientFactory: () => StartPtyResizeClient(),
        execOutputs: {
          // queue 尽きた後のフォールバック（収束確認の再ポーリング・同期）も
          // 94x39（実測変換式 cols-26 / rows-1 の期待値）を返す。
          'herdr api snapshot': kHerdrResizedSnapshotFixture,
        },
        execOutputQueues: {
          'herdr api snapshot': [
            kHerdrSnapshotWithLayoutFixture, // 接続時: area 80x24
            kHerdrSnapshotWithLayoutFixture, // ダイアログ初期値（currentPtySize）
            kHerdrSnapshotWithLayoutFixture, // ensureStarted の currentPtySize
            kHerdrResizedSnapshotFixture, // 収束確認: area 94x39（= 120-26 / 40-1）
            kHerdrResizedSnapshotFixture, // _syncAfterHerdrMutation
          ],
        },
      );

      await tester.tap(find.byTooltip('Resize Terminal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      // プリセット選択 → Resize ボタンで確定（hidden TUI ブリッジ経由）。
      await tester.tap(find.text('120x40 (Wide)'));
      await tester.pump();
      await tester.tap(find.text('Resize'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // 成功: fail closed SnackBar は出ない。
      expect(
        find.textContaining(
          'Resize failed. The terminal size could not be applied.',
        ),
        findsNothing,
        reason: '収束確認が成功した場合は fail closed 通知を出さない',
      );
      // hidden TUI の managed PTY が lazy start され、120x40 が送られた。
      final managed = (client as StartPtyResizeClient).managedProcesses;
      expect(managed, isNotEmpty, reason: 'lazy start で hidden TUI が起動される');
      expect(
        managed.last.resizes,
        contains((120, 40)),
        reason: 'PTY 要求サイズ 120x40 が managed PTY の window-change で送られる',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('セッションセレクタの Resize で PTY 要求サイズ変更を試みる'
        '（hidden TUI ブリッジ・fail closed 通知）', (tester) async {
      await pumpHerdrAndOpenWorkspaceSelector(tester);

      // ターミナル全体 resize は pane 数に依存しないため、resize 能力が
      // あれば常に表示される。
      expect(find.byTooltip('Resize Terminal'), findsOneWidget);

      await tester.tap(find.byTooltip('Resize Terminal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));

      // tmux の ResizeWindowDialog と同一構成（サイズ入力行 + プリセット +
      // Cancel/Resize ボタン・グリッドプレビュー省略）+ PTY 要求サイズの文言。
      expect(find.text('Resize Terminal'), findsOneWidget);
      expect(
        find.textContaining('Changes the size of the whole terminal'),
        findsOneWidget,
        reason: 'ユーザー選択 案4: ターミナル全体（PTY）のサイズ変更・全ワークスペースに適用（英語表記）',
      );
      expect(find.text('Cols'), findsOneWidget);
      expect(find.text('Rows'), findsOneWidget);
      expect(find.text('80x24 (Standard)'), findsOneWidget);
      expect(find.text('120x40 (Wide)'), findsOneWidget);

      // プリセット選択 → Resize ボタンで確定（hidden TUI ブリッジ経由）。
      await tester.tap(find.text('120x40 (Wide)'));
      await tester.pump();
      await tester.tap(find.text('Resize'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // FakeSshClient では hidden TUI（managed PTY）を起動できないため、
      // HerdrResizeBridge が start 失敗 → fail closed の SnackBar を表示する。
      expect(
        find.textContaining(
          'Resize failed. The terminal size could not be applied.',
        ),
        findsOneWidget,
        reason: 'resize 不達（他クライアント競合 or 表示設定不一致）は fail closed 通知',
      );

      // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 750));
    });

    testWidgets('Resize Terminal ダイアログのキャンセルは resize を試みない', (tester) async {
      await pumpHerdrAndOpenWorkspaceSelector(tester);

      await tester.tap(find.byTooltip('Resize Terminal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Resize Terminal'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // キャンセルは hidden TUI を起動せず resize しない（通知もなし）。
      expect(
        find.textContaining(
          'Resize failed. The terminal size could not be applied.',
        ),
        findsNothing,
        reason: 'キャンセルは bridge を起動しない（mounted ガード）',
      );

      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
