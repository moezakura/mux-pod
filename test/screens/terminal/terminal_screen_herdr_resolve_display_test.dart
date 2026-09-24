import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr (backend flow / display)', () {
    testWidgets('shows pane content without tmux setup', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'hello\nworld\n',
        },
        settle: false,
      );

      // tmux のセットアップ（バージョン確認・ツリー取得・セッション作成）は
      // herdr では一切実行されない。
      expect(client.execCommands.any((c) => c.contains('tmux -V')), isFalse);
      expect(
        client.execCommands.any((c) => c.contains('list-panes -a')),
        isFalse,
      );
      expect(client.execCommands.any((c) => c.contains('set-option')), isFalse);

      // スナップショットから pane を解決し、pane read で内容を取得する。
      expect(
        client.execCommands.any((c) => c.contains('herdr api snapshot')),
        isTrue,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains(
            'herdr pane read w1:p1 --source recent --lines 120 --raw',
          ),
        ),
        isTrue,
      );

      // 特殊キー入力バー（SpecialKeysBar）が表示される（mutation 有効）。
      // 未接続バナーは表示されない。
      expect(find.byType(SpecialKeysBar), findsOneWidget);
      expect(find.text('Not connected — viewing only'), findsNothing);

      // pane 内容が表示される
      expect(find.textContaining('hello'), findsWidgets);
      expect(find.textContaining('world'), findsWidgets);
    });
    testWidgets('ライブポーリングは持続的シェル経由（execPersistentCommands）で取得される'
        '（バグ2: 描画遅延の修正）', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      // ライブポーリング（--lines 120）は execPersistentWithExitCode 経由
      // （FakeSshClient は execPersistentCommands に記録）。
      expect(
        client.execPersistentCommands.any(
          (c) =>
              c.contains('herdr pane read w1:p1 --source recent --lines 120'),
        ),
        isTrue,
        reason: 'バグ2: herdr のライブポーリングは persistent shell 経由で取得されること',
      );
      // 内容は表示される（persistent 経由でも例外分類が維持される）
      expect(find.textContaining('hello'), findsWidgets);
    });
    testWidgets('深い履歴は exec チャネル経由で取得され、行数は scrollbackLines と整合する'
        '（tmux の capturePane 対比・バグ2 / バグ4）', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
          // 既定 scrollbackLines=10000 の要求行数（バグ4: 設定値と整合）。
          'herdr pane read w1:p1 --source recent --lines 10000 --raw':
              'deep-0\ndeep-1\n',
        },
        settle: false,
      );

      // スクロールモードに入れて深い履歴をロードする
      final dynamic state = tester.state(find.byType(TerminalScreen));
      state.loadHistoryForScrollForTesting();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      // 深い履歴は exec チャネル（execWithExitCode → execCommands）で取得され、
      // 要求行数はユーザー設定 scrollbackLines（既定 10000）と整合する。
      expect(
        client.execCommands.any(
          (c) =>
              c.contains('herdr pane read w1:p1 --source recent') &&
              c.contains('--lines 10000'),
        ),
        isTrue,
        reason:
            'バグ2: 深い履歴は大量出力のため exec チャネルで取得されること'
            'バグ4: 深い履歴の要求行数は scrollbackLines と整合すること',
      );
    });
    testWidgets(
      'sessionId disambiguates same-label workspaces (tmp w3/w4 pattern)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w2',
          execOutputs: {
            'herdr api snapshot': kHerdrSameLabelSnapshotFixture,
            'herdr pane read': 'content from w2\n',
          },
          settle: false,
        );

        // sessionId 優先（id 一致 → label 一致 → フォールバック）:
        // 同名ラベル "tmp" でも w2 の pane が解決される。
        expect(
          client.execCommands.any(
            (c) => c.contains(
              'herdr pane read w2:p1 --source recent --lines 120 --raw',
            ),
          ),
          isTrue,
        );
        // focused_workspace_id は w1 だが、sessionId=w2 なので w1:p1 は読まない
        expect(
          client.execCommands.any(
            (c) => c.contains(
              'herdr pane read w1:p1 --source recent --lines 120 --raw',
            ),
          ),
          isFalse,
        );
        expect(find.textContaining('content from w2'), findsWidgets);
      },
    );
    testWidgets(
      'sessionId not in snapshot falls back to same-label workspace resolution',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w9', // 存在しない ID → label 一致にフォールバック
          execOutputs: {
            'herdr api snapshot': kHerdrSameLabelSnapshotFixture,
            'herdr pane read': 'content from fallback\n',
          },
          settle: false,
        );

        // 存在しない sessionId では label 一致（先頭の "tmp" workspace = w1）へ
        // フォールバックする（resolver の workspaceLabel 経路）。
        expect(
          client.execCommands.any(
            (c) => c.contains(
              'herdr pane read w1:p1 --source recent --lines 120 --raw',
            ),
          ),
          isTrue,
        );
        expect(find.textContaining('content from fallback'), findsWidgets);
      },
    );
    testWidgets(
      'legacy sessionId-null entry on empty snapshot shows the error and '
      'records diagnostic events (No herdr pane found root cause)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          // 旧データ（sessionId: null）の "tmp" エントリから遷移した状態。
          sessionName: 'tmp',
          execOutputs: {
            // snapshot に workspace / pane が 1 件も無い（herdr サーバ空）。
            'herdr api snapshot': kHerdrEmptySnapshotFixture,
          },
          settle: false,
        );

        // 通信エラーパネルに「No herdr pane found for this workspace」
        expect(find.byKey(const Key('comm_error_panel')), findsOneWidget);
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pump();
        expect(
          find.textContaining('No herdr pane found', findRichText: true),
          findsWidgets,
        );

        // 診断ログがリングバッファ（[HerdrSwitch]）に記録される。
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('resolve failed: no pane in snapshot')),
          isTrue,
          reason: 'resolver の解決失敗理由（workspaces/panes 件数）が記録されること',
        );
        expect(
          events.any(
            (e) => e.contains('initial resolve failed: no pane found'),
          ),
          isTrue,
          reason: '初期解決失敗（要求 sessionId/label 付き）が記録されること',
        );
      },
    );
    testWidgets(
      'snapshot fetch failure (HerdrCommandException) records diagnostic '
      'events with errorCode/exitCode (No herdr pane found root cause)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w4',
          // `herdr api snapshot` が exit 1 で失敗する（server-down 相当・
          // stderr は fake が空文字のため "herdr command failed (exit code: 1)"）。
          execExitCodes: {'herdr api snapshot': 1},
          settle: false,
        );

        // 通信エラーパネルに「No herdr pane found for this workspace」
        expect(find.byKey(const Key('comm_error_panel')), findsOneWidget);
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pump();
        expect(
          find.textContaining('No herdr pane found', findRichText: true),
          findsWidgets,
        );

        // catch 経路の診断ログ（例外種別 + errorCode + exitCode）が記録される。
        final events = herdrSwitchEvents(tester);
        expect(
          events.any(
            (e) =>
                e.contains('initial resolve failed: snapshot fetch error') &&
                e.contains('type=HerdrCommandException') &&
                e.contains('errorCode=<null>') &&
                e.contains('exitCode=1'),
          ),
          isTrue,
          reason: 'HerdrCommandException の種別・errorCode・exitCode が記録されること',
        );
        expect(
          events.any(
            (e) => e.contains('initial resolve failed: no pane found'),
          ),
          isTrue,
          reason: '最終的に「No herdr pane found」に帰着したことが記録されること',
        );
      },
    );
    testWidgets('snapshot fetch failure (HerdrTargetNotFoundException) records '
        'diagnostic events with kind/errorCode', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'tmp',
        sessionId: 'w4',
        // `herdr api snapshot` が構造化エラー
        // `{"error":{"code":"workspace_not_found",...}}` を返して exit 1。
        execOutputs: {
          'herdr api snapshot':
              '{"error":{"code":"workspace_not_found","message":"no workspace"}}',
        },
        execExitCodes: {'herdr api snapshot': 1},
        settle: false,
      );

      expect(find.byKey(const Key('comm_error_panel')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(
        find.textContaining('No herdr pane found', findRichText: true),
        findsWidgets,
      );

      final events = herdrSwitchEvents(tester);
      expect(
        events.any(
          (e) =>
              e.contains(
                'initial resolve failed: target not found in snapshot',
              ) &&
              e.contains('type=HerdrTargetNotFoundException') &&
              e.contains('kind=HerdrTargetNotFoundKind.workspace') &&
              e.contains('errorCode=workspace_not_found'),
        ),
        isTrue,
        reason: 'HerdrTargetNotFoundException の種別・kind・errorCode が記録されること',
      );
    });
    testWidgets('uses an injected paneContentReader when provided', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        initialPaneId: 'w1:p1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'injected content\n',
        },
        settle: false,
      );

      // 直接 pane ID 指定ならスナップショットに依存せず read する
      expect(
        client.execCommands.any(
          (c) => c.contains(
            'herdr pane read w1:p1 --source recent --lines 120 --raw',
          ),
        ),
        isTrue,
      );
      expect(find.textContaining('injected content'), findsWidgets);
    });
  });
}
