import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_content_reader.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/widgets/multiplexer_tiles.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';

import '../../helpers/fake_ssh_notifier.dart';
import '../../helpers/terminal_test_scaffold.dart';

// A8 最小監視のテスト: `_TerminalScreenState` のリングバッファを
// `@visibleForTesting` フック（herdrSwitchEventsForTesting）経由で読み出す。
// イベント文字列には `[HerdrSwitch]` プレフィックスが含まれ、debugPrint に
// 出力される文字列と同一である。
List<String> herdrSwitchEvents(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(TerminalScreen));
  return List<String>.from(state.herdrSwitchEventsForTesting());
}

// M2: pane indicator（右上ミニマップ）の描画判定。`_PaneLayoutPainter` は
// `terminal_screen.dart` の private クラスのため runtimeType 名で特定する。
Finder paneIndicatorPainter() => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_PaneLayoutPainter',
);

/// 初回のポーリング read は成功し、[failNextPoll] 後は target-not-found で
/// 失敗する reader（T3: 再解決の tabId 伝播検証用）。
///
/// 直接指定（initialPaneId）の初期表示を安定させた後、任意のタイミングで
/// 再解決（強制再取得 → `_switchHerdrTarget`）を発火させられる。
class _ReResolvePropagationReader implements PaneContentReader {
  String pollContent = 'content from p1\n';
  bool failNextPoll = false;

  @override
  Future<MultiplexerPaneSnapshot> readPane({
    required String paneId,
    int? historyLines,
    String source = 'recent',
  }) async {
    if (failNextPoll) {
      failNextPoll = false;
      throw const HerdrTargetNotFoundException(
        kind: HerdrTargetNotFoundKind.pane,
        message: 'no such pane',
        errorCode: 'pane_not_found',
        exitCode: 1,
      );
    }
    return MultiplexerPaneSnapshot(content: pollContent);
  }
}

// G4 実測のスナップショット fixture（workspace label は lab-ws1 / pane は w1:p1）。
const kHerdrSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// layout 付き snapshot fixture（バグ1 AutoFit 用）: pane w1:p1 の rect が
// 幅 120 x 高さ 24（文字セル単位・T0 実測⑥）。AutoFit がこの幅で計算される
// ことを検証する（従来は layout が空のため width/height=0 → 既定 80 のまま）。
const kHerdrSnapshotWithLayoutFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[{"area":{"height":24,"width":120,'
    '"x":0,"y":0},"focused_pane_id":"w1:p1","panes":[{"focused":true,'
    '"pane_id":"w1:p1","rect":{"height":24,"width":120,"x":0,"y":0}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// zoom 中 snapshot fixture（バグ1 AutoFit 用）: zoomed=true のとき pane 表示は
// タブ全面（layout.area）になる（T0 実測 6-b）。pane rect は非 zoom 値
// （width 40）のままでも、AutoFit は area の幅 120 を使うことを検証する。
const kHerdrSnapshotZoomedFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[{"area":{"height":24,"width":120,'
    '"x":0,"y":0},"focused_pane_id":"w1:p1","panes":[{"focused":true,'
    '"pane_id":"w1:p1","rect":{"height":24,"width":40,"x":0,"y":0}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":true}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 再解決後（pane 差し替え後）の snapshot fixture: pane は w1:p2 のみ。
const kHerdrSnapshotPane2Fixture =    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p2","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 対象が存在しない（panes 空）snapshot fixture（再解決の終端判定用）。
const kHerdrEmptySnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":null,"focused_tab_id":null,"focused_workspace_id":null,'
    '"layouts":[],"panes":[],"protocol":17,"tabs":[],"version":"0.7.5",'
    '"workspaces":[]},"type":"session_snapshot"}}';

// 同名ラベル "tmp" の 2 workspace（w1/w2）fixture。
// herdr の実測と同じく label が重複するケース（tmp w3/w4）を模し、
// sessionId 優先（id 一致 → label 一致 → フォールバック）の解決を検証する。
// w1:p1（focused・cwd=/tmp）/ w2:p1（cwd=/var）。
const kHerdrSameLabelSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/var","focused":false,'
    '"foreground_cwd":"/var","pane_id":"w2:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w2:t1",'
    '"terminal_id":"term_2","workspace_id":"w2"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w2:t1","workspace_id":"w2"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"tmp","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"},'
    '{"active_tab_id":"w2:t1","agent_status":"unknown","focused":false,'
    '"label":"tmp","number":1,"pane_count":1,"tab_count":1,'
    '"workspace_id":"w2"}]},"type":"session_snapshot"}}';

// T10 セレクタ用: 2 workspace（w1/w2）の snapshot fixture。
// w1:p1（cwd=/tmp・focused）/ w2:p1（cwd=/var）を持ち、セレクタの
// workspace → tab → pane ドリルダウンと pane 表示名（A10: currentPath 優先）
// を検証できる。
const kHerdrTwoWorkspaceSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/var","focused":false,'
    '"foreground_cwd":"/var","pane_id":"w2:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w2:t1",'
    '"terminal_id":"term_2","workspace_id":"w2"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w2:t1","workspace_id":"w2"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"},'
    '{"active_tab_id":"w2:t1","agent_status":"unknown","focused":false,'
    '"label":"lab-ws2","number":1,"pane_count":1,"tab_count":1,'
    '"workspace_id":"w2"}]},"type":"session_snapshot"}}';

// M-4 検証用: tab に数字以外の実ラベル（"editor"）を持つ snapshot fixture。
// パンくずの tab セグメントが数字抽出（"1"）ではなく実ラベルを表示することを
// 検証する（T4）。
const kHerdrLabeledTabSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"editor","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

Connection _herdrConnection() {
  return Connection(
    id: 'test-conn',
    name: 'Herdr Server',
    host: 'testhost',
    port: 22,
    username: 'user',
    multiplexer: const MultiplexerConfig(backend: BackendType.herdr),
    createdAt: DateTime(2025, 1, 1),
  );
}

void main() {
  group('TerminalScreen herdr (read-only)', () {
    testWidgets('shows pane content read-only without tmux setup', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
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

      // read-only 表示（バナー + パンくずバッジ）
      expect(find.text('READ ONLY — viewing only'), findsOneWidget);
      expect(find.text('Read-only'), findsOneWidget);

      // 特殊キー入力バーは表示されない（mutation 無効化）
      expect(find.byType(SpecialKeysBar), findsNothing);

      // pane 内容が表示される
      expect(find.textContaining('hello'), findsWidgets);
      expect(find.textContaining('world'), findsWidgets);
    });

    testWidgets(
      'ライブポーリングは持続的シェル経由（execPersistentCommands）で取得される'
      '（バグ2: 描画遅延の修正）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
            (c) => c.contains('herdr pane read w1:p1 --source recent --lines 120'),
          ),
          isTrue,
          reason: 'バグ2: herdr のライブポーリングは persistent shell 経由で取得されること',
        );
        // 内容は表示される（persistent 経由でも例外分類が維持される）
        expect(find.textContaining('hello'), findsWidgets);
      },
    );

    testWidgets(
      '深い履歴は exec チャネル経由で取得され、行数は scrollbackLines と整合する'
      '（tmux の capturePane 対比・バグ2 / バグ4）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
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
          reason: 'バグ2: 深い履歴は大量出力のため exec チャネルで取得されること'
              'バグ4: 深い履歴の要求行数は scrollbackLines と整合すること',
        );
      },
    );

    testWidgets(
      'sessionId disambiguates same-label workspaces (tmp w3/w4 pattern)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w2',
          readOnly: true,
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
          connection: _herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w9', // 存在しない ID → label 一致にフォールバック
          readOnly: true,
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
          connection: _herdrConnection(),
          // 旧データ（sessionId: null）の "tmp" エントリから遷移した状態。
          sessionName: 'tmp',
          readOnly: true,
          execOutputs: {
            // snapshot に workspace / pane が 1 件も無い（herdr サーバ空）。
            'herdr api snapshot': kHerdrEmptySnapshotFixture,
          },
          settle: false,
        );

        // エラーオーバーレイに「No herdr pane found for this workspace」
        expect(find.textContaining('No herdr pane found'), findsWidgets);

        // 診断ログがリングバッファ（[HerdrSwitch]）に記録される。
        final events = herdrSwitchEvents(tester);
        expect(
          events.any(
            (e) => e.contains('resolve failed: no pane in snapshot'),
          ),
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
          connection: _herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w4',
          readOnly: true,
          // `herdr api snapshot` が exit 1 で失敗する（server-down 相当・
          // stderr は fake が空文字のため "herdr command failed (exit code: 1)"）。
          execExitCodes: {
            'herdr api snapshot': 1,
          },
          settle: false,
        );

        // エラーオーバーレイに「No herdr pane found for this workspace」
        expect(find.textContaining('No herdr pane found'), findsWidgets);

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
          events.any((e) => e.contains('initial resolve failed: no pane found')),
          isTrue,
          reason: '最終的に「No herdr pane found」に帰着したことが記録されること',
        );
      },
    );

    testWidgets(
      'snapshot fetch failure (HerdrTargetNotFoundException) records '
      'diagnostic events with kind/errorCode',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w4',
          readOnly: true,
          // `herdr api snapshot` が構造化エラー
          // `{"error":{"code":"workspace_not_found",...}}` を返して exit 1。
          execOutputs: {
            'herdr api snapshot':
                '{"error":{"code":"workspace_not_found","message":"no workspace"}}',
          },
          execExitCodes: {
            'herdr api snapshot': 1,
          },
          settle: false,
        );

        expect(find.textContaining('No herdr pane found'), findsWidgets);

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
      },
    );

    testWidgets('uses an injected paneContentReader when provided', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
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

    testWidgets(
      'breadcrumb shows workspace label, tab segment, pane segment, and '
      'display-only read-only badge (A9 display state / T11 / T4)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // workspace ラベル + tab セグメント + pane セグメント + Read-only バッジ
        // （T11）。tabId はスナップショット解決済みの実値（w1:t1）を保持するため、
        // 2 セグメント pane ID（w1:p1）でも tab セグメント "1"（実ラベル）が
        // 表示される（L-1 / M-4）。
        expect(find.text('lab-ws1'), findsOneWidget);
        expect(find.text('1'), findsOneWidget); // tab セグメント（実ラベル '1'）
        expect(find.byIcon(Icons.tab), findsOneWidget);
        expect(find.text('Pane 1'), findsOneWidget);
        expect(find.text('Read-only'), findsOneWidget);

        // T4: セッション（workspace）セグメントのタップで共通シートの
        // workspace 一覧（第 1 段）が開く
        await tester.tap(find.text('lab-ws1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsOneWidget);
      },
    );

    testWidgets(
      'T4: Read-only badge is display-only and does not open a selector',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // バッジは表示のみ（非インタラクティブ）: タップしてもセレクタは開かない
        await tester.tap(find.text('Read-only'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsNothing);
      },
    );

    testWidgets(
      'T4: tab segment tap opens the selector at the tab stage (stage 2)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // tab セグメント（snapshot 解決済みラベル '1'）タップ → 現在 workspace の
        // tab 一覧（第 2 段）が開く
        await tester.tap(find.text('1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Window'), findsOneWidget);
        // 現在 workspace（lab-ws1）の tab が表示される（index: name）
        expect(find.text('1: 1'), findsOneWidget);
      },
    );

    testWidgets(
      'T4: pane segment tap opens the selector at the pane stage (stage 3)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // pane セグメント（'Pane 1'）タップ → 現在 tab の pane 一覧（第 3 段）
        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Pane'), findsOneWidget);
        // A10: pane 表示名は cwd（/tmp）優先
        expect(find.text('/tmp'), findsOneWidget);
      },
    );

    testWidgets(
      'M-4: tab segment shows the snapshot-resolved tab label (not a number)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrLabeledTabSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // 旧実装（数字抽出）なら '1' になるが、M-4 では実ラベル 'editor' を表示する
        expect(find.text('editor'), findsOneWidget);
        expect(find.text('1'), findsNothing);
      },
    );

    testWidgets(
      'monitors server-down detection in the [HerdrSwitch] ring buffer (A8/T5b)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            // 構造化エラー: server 未稼働系 errorCode（A1 条件2）
            'herdr pane read':
                '{"error":{"code":"connection_refused","message":"connect refused"}}',
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );
        // ポーリングの catch を発火させる（初回ポーリングで pane read が失敗する）
        await tester.pump(const Duration(milliseconds: 200));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('server-down detected')),
          isTrue,
          reason: 'server-down 検出がリングバッファに [HerdrSwitch] 付きで記録されること',
        );
        expect(
          events.where((e) => e.startsWith('[HerdrSwitch]')).length,
          greaterThanOrEqualTo(1),
        );
      },
    );

    testWidgets(
      'monitors target-not-found detection in the [HerdrSwitch] ring buffer (A8/T5b)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            // 構造化エラー: target 不在（A2 再解決トリガ）
            'herdr pane read':
                '{"error":{"code":"pane_not_found","message":"no such pane"}}',
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 200));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('target-not-found detected')),
          isTrue,
          reason: 'target-not-found 検出がリングバッファに [HerdrSwitch] 付きで記録されること',
        );
      },
    );

    testWidgets(
      'switch commit updates display state and polling target without mutation (A4/T6)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          initialPaneId: 'w1:p1',
          execOutputs: {'herdr pane read': 'content\n'},
          settle: false,
        );

        // 初期表示は w1:p1 を read している
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
        );

        // 切替コミットを実行（本番の呼び出し元はセレクタ T10。テストフックは
        // `_switchHerdrTarget` を直接呼ぶ = 切替コミットの単一入口の検証）
        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.switchHerdrTargetForTesting('w1:p2');
        await tester.pump();

        // 表示対象切替イベントがリングバッファに [HerdrSwitch] 付きで記録される（A8）
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('switch target -> w1:p2')),
          isTrue,
          reason: '表示対象切替がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // コンテンツクリア + boostPolling: 次のポーリングで新ターゲットを read する
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p2')),
          isTrue,
          reason: '切替後に新しい pane ID がポーリング対象になること',
        );

        // read-only: mutation（select-pane 等の tmux/herdr CLI）は一切発行されない
        expect(
          client.execCommands.any((c) => c.contains('select-pane')),
          isFalse,
        );
        expect(
          client.execCommands.any((c) => c.contains('herdr pane focus')),
          isFalse,
        );
      },
    );

    testWidgets(
      'switch to the same target is a no-op (L-3: no flicker)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          initialPaneId: 'w1:p1',
          execOutputs: {'herdr pane read': 'content\n'},
          settle: false,
        );

        // 直接指定（initialPaneId）の初期表示: workspaceId 'w1' / tabId null。
        // 同一ターゲット（paneId / workspaceId / tabId が全て一致）への切替は
        // no-op で、表示リセット・切替イベント・ポーリングブーストを抑止する。
        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.switchHerdrTargetForTesting('w1:p1');
        await tester.pump();

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('switch target')),
          isFalse,
          reason: '同一ターゲットへの切替は no-op で切替イベントを記録しないこと',
        );

        // 表示内容が維持されている（no-op でコンテンツがクリアされない）
        expect(find.textContaining('content'), findsWidgets);
      },
    );

    testWidgets(
      'server-down stops polling, shows SnackBar with retry, no reconnect '
      '(A2/T7)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            // 構造化エラー: server 未稼働系 errorCode（A1 条件2）
            'herdr pane read':
                '{"error":{"code":"connection_refused","message":"connect refused"}}',
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );

        // 初回ポーリングで server-down を検出し、ポーリングを停止する
        await tester.pump(const Duration(milliseconds: 200));

        // 監視（A8）: server-down 検出がリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('server-down')),
          isTrue,
          reason: 'server-down 検出がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // SnackBar + Retry（Retry = 再試行）が表示される
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // 再接続しない（R1）: server-down は再接続ループにせずポーリング停止
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(
          notifier.reconnectCalls,
          0,
          reason: 'server-down では再接続せずポーリングを停止すること',
        );

        // ポーリング停止: 以降 pane read が増えない
        final readsAfterDown = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        await tester.pump(const Duration(milliseconds: 500));
        final readsLater = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        expect(
          readsLater,
          readsAfterDown,
          reason: 'server-down 後はポーリングが停止し pane read が増えないこと',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'target-not-found re-resolves via forced snapshot and switches pane '
      '(A2/T7)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            // フォールバック: 3 回目以降の snapshot は再取得済み（w1:p2）を返す
            'herdr api snapshot': kHerdrSnapshotPane2Fixture,
            'herdr pane read w1:p1':
                '{"error":{"code":"pane_not_found","message":"no such pane"}}',
            'herdr pane read w1:p2': 'hello from p2\n',
          },
          // 1 回目（接続時解決）: w1:p1 / 2 回目（強制再取得）: w1:p2
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotPane2Fixture,
            ],
          },
          execExitCodes: {'herdr pane read w1:p1': 1},
          settle: false,
        );

        // pane read w1:p1 が pane_not_found → 強制再取得で w1:p2 へ再解決
        await tester.pump(const Duration(milliseconds: 300));

        // 監視（A8）: 再解決成功がリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve succeeded -> w1:p2')),
          isTrue,
          reason: '再解決成功がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // 表示対象が w1:p2 へ切り替わり、次のポーリングが新ターゲットを読む
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p2')),
          isTrue,
          reason: '再解決後は新しい pane ID がポーリング対象になること',
        );
        expect(find.textContaining('hello from p2'), findsWidgets);

        // 再接続は発生しない（再解決は再接続ではなく表示継続）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(
          notifier.reconnectCalls,
          0,
          reason: 'target-not-found の再解決は再接続を伴わないこと',
        );
      },
    );

    testWidgets(
      're-resolve propagates the snapshot tabId/workspaceId into the display '
      'state (T3)',
      (tester) async {
        final reader = _ReResolvePropagationReader();

        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          initialPaneId: 'w1:p1',
          paneContentReader: reader,
          // 直接指定（initialPaneId）のため初回の snapshot 取得は再解決時のみ
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotPane2Fixture,
          },
          settle: false,
        );

        // 直接指定の初期表示では tabId 未確定（2 セグメント pane ID）のため
        // tab セグメントは非表示。
        expect(find.byIcon(Icons.tab), findsNothing);
        expect(find.textContaining('content from p1'), findsWidgets);

        // 次のポーリング read を target-not-found で失敗 → 強制再取得（w1:p2 の
        // snapshot）で再解決し、_switchHerdrTarget へ tabId / workspaceId が
        // 伝播する。再解決後のポーリング内容も差し替えておく。
        reader.failNextPoll = true;
        reader.pollContent = 'hello from p2\n';
        // 失敗ポーリング → 強制再取得 → 再解決 → 切替コミット
        await tester.pump(const Duration(milliseconds: 300));
        // 切替後のブーストポーリングが新ターゲットを読み、内容が反映される
        await tester.pump(const Duration(milliseconds: 300));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve succeeded -> w1:p2')),
          isTrue,
          reason: '再解決成功がリングバッファに記録されること',
        );

        // 表示が w1:p2 に切り替わり、新しい pane の内容が表示される
        expect(
          find.textContaining('hello from p2'),
          findsWidgets,
          reason: '再解決後は新しい pane の内容が表示されること',
        );

        // 再解決後の表示状態に snapshot 実値（w1:p2 → tabId w1:t1）が反映され、
        // パンくずに tab セグメントが表示される。
        expect(
          find.byIcon(Icons.tab),
          findsOneWidget,
          reason: '再解決で確定した tabId が表示状態へ伝播し tab セグメントが表示されること',
        );
      },
    );

    testWidgets(
      'target-not-found terminal: re-resolve failure stops polling without '
      'reconnect (A2/T7)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            // フォールバック: 3 回目以降の snapshot も空（対象不在）
            'herdr api snapshot': kHerdrEmptySnapshotFixture,
            'herdr pane read':
                '{"error":{"code":"pane_not_found","message":"no such pane"}}',
          },
          // 1 回目（接続時解決）: w1:p1 / 2 回目（強制再取得）: 対象なし
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrEmptySnapshotFixture,
            ],
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );

        await tester.pump(const Duration(milliseconds: 300));

        // 監視（A8）: 再解決失敗がリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve failed')),
          isTrue,
          reason: '再解決失敗がリングバッファに [HerdrSwitch] 付きで記録されること',
        );

        // 終端: 再接続しない（R1）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(notifier.reconnectCalls, 0, reason: '再解決失敗の終端では再接続しないこと');

        // SnackBar 通知（Retry = 再試行）
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // 終端後はポーリングが停止し pane read が増えない
        final readsAfterTerminal = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        await tester.pump(const Duration(milliseconds: 500));
        final readsLater = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        expect(
          readsLater,
          readsAfterTerminal,
          reason: '終端後はポーリングが停止し pane read が増えないこと',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'herdr reconnect re-resolves the target from a fresh snapshot and keeps '
      'polling without tmux tree refresh (T9a)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            // フォールバック: 3 回目以降の snapshot も再取得済み（w1:p2）を返す
            'herdr api snapshot': kHerdrSnapshotPane2Fixture,
            'herdr pane read w1:p1': 'content from p1\n',
            'herdr pane read w1:p2': 'content from p2\n',
          },
          // 1 回目（接続時解決）: w1:p1 / 2 回目（再接続後再解決）: w1:p2
          execOutputQueues: {
            'herdr api snapshot': [
              kHerdrSnapshotFixture,
              kHerdrSnapshotPane2Fixture,
            ],
          },
          settle: false,
        );

        // 初回表示: w1:p1 を read している
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
        );

        // 再接続成功（SshNotifier のコールバック経由）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        notifier.onReconnectSuccess?.call();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // _applyUpdate が post-frame に延期される場合があるため、描画を確定させる
        await tester.pump();

        // 再接続後: 新 adapter の cache（`identical` 差し替え検出）経由で snapshot を
        // 再取得し、ターゲットを w1:p2 へ再解決する（エポック++ は cache 内在）
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve after reconnect -> w1:p2')),
          isTrue,
          reason: '再接続後のターゲット再解決がリングバッファに記録されること',
        );

        // 表示が w1:p2 に切り替わり、ポーリングが新ターゲットを読む
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p2')),
          isTrue,
          reason: '再接続後のポーリングは再解決した新しい pane ID を読むこと',
        );
        expect(find.textContaining('content from p2'), findsWidgets);

        // tmux ツリー更新は herdr では発火しない（既存バグ修正・A7）
        expect(
          client.execCommands.any((c) => c.contains('list-panes -a')),
          isFalse,
          reason: 'herdr では _startTreeRefresh（list-panes）を起動しないこと',
        );

        // 再接続後初回コンテンツ適用でスケジュールされる _scrollToCaret の
        // 100ms 遅延タイマーを消化する（ポーリングタイマーは dispose が破棄する）
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'herdr reconnect to the same pane keeps the display without a switch '
      '(T9a)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read w1:p1': 'content from p1\n',
          },
          settle: false,
        );

        expect(find.textContaining('content from p1'), findsWidgets);

        // 再接続成功（同一 snapshot に再解決 → 切替コミットなし）
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        notifier.onReconnectSuccess?.call();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('re-resolve after reconnect -> w1:p1')),
          isTrue,
          reason: '再接続後の再解決（同一 pane）が記録されること',
        );
        expect(
          events.any((e) => e.contains('switch target')),
          isFalse,
          reason: '同一 pane への再解決では切替コミットが発生しないこと',
        );

        // 表示は継続され、ポーリングも同じ pane を読み続ける
        expect(find.textContaining('content from p1'), findsWidgets);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
          reason: '再接続後も同一 pane のポーリングが継続すること',
        );
      },
    );

    testWidgets(
      'herdr lifecycle: resume restarts polling after server-down suspension '
      'without tmux tree refresh (T9b)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            // 構造化エラー: server 未稼働系 errorCode（A1 条件2）
            'herdr pane read':
                '{"error":{"code":"connection_refused","message":"connect refused"}}',
          },
          execExitCodes: {'herdr pane read': 1},
          settle: false,
        );

        // 初回ポーリングで server-down を検出しポーリング停止
        await tester.pump(const Duration(milliseconds: 200));
        final readsAfterDown = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        await tester.pump(const Duration(milliseconds: 500));
        final readsLater = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        expect(
          readsLater,
          readsAfterDown,
          reason: 'server-down 後はポーリングが停止していること',
        );

        // バックグラウンドへ → フォアグラウンド復帰
        // （herdr: サーバー復旧を再検証してポーリングを再開する）
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        // tmux ツリー更新は発火しない（A7）
        expect(
          client.execCommands.any((c) => c.contains('list-panes -a')),
          isFalse,
          reason: 'herdr では復帰時も _startTreeRefresh を起動しないこと',
        );

        // ポーリング再開: 次回 read が server-down で再停止 + SnackBar 通知
        await tester.pump(const Duration(milliseconds: 300));
        final readsAfterResume = client.execCommands
            .where((c) => c.contains('herdr pane read'))
            .length;
        expect(
          readsAfterResume,
          greaterThan(readsLater),
          reason: '復帰時に server-down 停止状態からポーリングが再開されること',
        );
        expect(find.byType(SnackBar), findsOneWidget);

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );

    testWidgets(
      'herdr lifecycle: dispose cleans up snapshot cache and ring buffer '
      'without exceptions (T9b)',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(TerminalScreen)),
        );
        final notifier =
            container.read(sshProvider.notifier) as FakeSshNotifier;
        expect(notifier.onReconnectSuccess, isNotNull);

        // 画面破棄で HerdrSnapshotCache / リングバッファ等を例外なくクリーンアップ
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(notifier.onReconnectSuccess, isNull);
        expect(notifier.onDisconnectDetected, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'T10 selectors (workspace → tab → pane) each close on selection and '
      'switch the displayed pane via the single commit without mutation',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrTwoWorkspaceSnapshotFixture,
            'herdr pane read w1:p1': 'content from p1\n',
            'herdr pane read w2:p1': 'content from p2\n',
          },
          settle: false,
        );

        // 初期表示は w1:p1（snapshot から解決）
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w1:p1')),
          isTrue,
        );

        // workspace セレクタ（Select Session 相当）: セッションセグメントタップ
        await tester.tap(find.text('lab-ws1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsOneWidget);
        expect(find.text('lab-ws2'), findsOneWidget);

        // workspace 選択 → シート即閉じ + 切替コミット（workspace のフォーカス pane）
        await tester.tap(
          find.byKey(const ValueKey('mux-sel-session-lab-ws2')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsNothing);
        expect(find.text('Select Window'), findsNothing);

        // A8 監視: 切替イベントがリングバッファに記録される
        final events = herdrSwitchEvents(tester);
        expect(
          events.any((e) => e.contains('switch target -> w2:p1')),
          isTrue,
          reason: 'workspace 選択が切替コミット（_switchHerdrTarget）を呼ぶこと',
        );

        // ポーリングが新しいターゲットを読む
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          client.execCommands.any((c) => c.contains('herdr pane read w2:p1')),
          isTrue,
          reason: '切替後に新しい pane ID がポーリング対象になること',
        );
        expect(find.textContaining('content from p2'), findsWidgets);
        // T11: ブレッドクラムの workspace ラベルが選択結果へ更新される
        expect(
          find.text('lab-ws2'),
          findsOneWidget,
          reason: 'パンくずの workspace 名が選択結果のラベルに更新されること',
        );

        // tab セレクタ（Select Window 相当）: 現在 workspace（lab-ws2）の tab 一覧
        await tester.tap(find.text('1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Window'), findsOneWidget);
        expect(find.text('1: 1'), findsOneWidget);

        // tab 選択 → シート即閉じ（切替先は同一ターゲットのため no-op）
        await tester.tap(find.byKey(const ValueKey('mux-sel-window-w2:t1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Window'), findsNothing);
        expect(find.text('Select Pane'), findsNothing);

        // pane セレクタ（Select Pane 相当）: 現在 tab の pane 一覧。
        // A10: pane 表示名は currentPath（cwd=/var）を優先する
        await tester.tap(find.text('Pane 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Pane'), findsOneWidget);
        expect(find.text('/var'), findsOneWidget);

        // pane 選択 → シート即閉じ + 切替コミット
        await tester.tap(find.byKey(const ValueKey('mux-sel-pane-w2:p1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Pane'), findsNothing);

        // read-only（A6）: セレクタ経由でも mutation コマンドは一切発行されない
        expect(
          client.execCommands.any((c) => c.contains('select-pane')),
          isFalse,
        );
        expect(
          client.execCommands.any((c) => c.contains('herdr pane focus')),
          isFalse,
        );
      },
    );

    testWidgets('T10 selectors highlight the current display target as initial '
        'emphasis (workspace/tab/pane)', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        settle: false,
      );

      // workspace セレクタ（Select Session 相当）: 現在ターゲット（w1:p1）が
      // 属する workspace が active 表示（ActiveListTile のアクティブ時は title が
      // 太字になる）
      await tester.tap(find.text('lab-ws1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Session'), findsOneWidget);
      final wsTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('mux-sel-session-lab-ws1')),
          matching: find.text('lab-ws1'),
        ),
      );
      expect(wsTitle.style?.fontWeight, FontWeight.bold);

      // シートを閉じて tab セレクタを開く: 現在 tab（w1:t1）が active 表示
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Session'), findsNothing);

      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Window'), findsOneWidget);
      final tabTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('mux-sel-window-w1:t1')),
          matching: find.text('1: 1'),
        ),
      );
      expect(tabTitle.style?.fontWeight, FontWeight.bold);

      // シートを閉じて pane セレクタを開く: 現在 pane（w1:p1、cwd=/tmp）が
      // active 表示。pane 表示名は cwd（A10）を優先する
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Window'), findsNothing);

      await tester.tap(find.text('Pane 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsOneWidget);
      expect(find.text('/tmp'), findsOneWidget);
      final paneTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('mux-sel-pane-w1:p1')),
          matching: find.text('/tmp'),
        ),
      );
      expect(paneTitle.style?.fontWeight, FontWeight.bold);

      // セレクタを閉じる
      await tester.tapAt(const Offset(500, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Select Pane'), findsNothing);
    });

    testWidgets(
      'H-1 same-label workspaces (tmp w3/w4 pattern) highlight only the '
      'sessionId-matched workspace in the session selector',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'tmp',
          sessionId: 'w2',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSameLabelSnapshotFixture,
            'herdr pane read': 'content from w2\n',
          },
          settle: false,
        );

        // 現在ターゲットは sessionId=w2 の workspace（w2:p1）に解決される。
        // workspace セレクタ（Select Session 相当）を開く。
        await tester.tap(find.text('tmp'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsOneWidget);

        // 同名ラベル "tmp" の workspace が w1 / w2 の 2 つ表示される。
        final tiles = tester
            .widgetList<MultiplexerSessionTile>(
              find.byType(MultiplexerSessionTile),
            )
            .toList();
        expect(tiles, hasLength(2));
        expect(tiles.map((t) => t.session.name).toSet(), {'tmp'});

        // ハイライトは ID を一義的な基準とする:
        // sessionId 一致（w2）の workspace だけが active になり、
        // 同名ラベルでも ID 不一致（w1）は active にならない。
        final activeById = {for (final t in tiles) t.session.id: t.isActive};
        expect(
          activeById['w2'],
          isTrue,
          reason: '現在の workspace ID（w2）だけがハイライトされること',
        );
        expect(
          activeById['w1'],
          isFalse,
          reason: '同名ラベル "tmp" でも ID 不一致（w1）はハイライトされないこと',
        );
      },
    );

    testWidgets('M2: herdr (read-only) では stale な tmux 複数ペイン状態でも pane '
        'indicator を表示せず mutation を発行しない', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        readOnly: true,
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        settle: false,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalScreen)),
      );

      // stale な tmuxProvider 状態を作る: 2 ペインのアクティブウィンドウを注入。
      // herdr 経路では tmuxProvider は更新されないため、接続前の残骸が残りうる。
      final tmuxNotifier = container.read(tmuxProvider.notifier);
      tmuxNotifier.updateSessions([
        TmuxSession(
          name: 'stale-session',
          windows: [
            TmuxWindow(
              index: 0,
              name: 'stale-win',
              panes: const [
                TmuxPane(index: 0, id: 'stale-p1', active: true),
                TmuxPane(index: 1, id: 'stale-p2'),
              ],
            ),
          ],
        ),
      ]);
      tmuxNotifier.setActive(
        sessionName: 'stale-session',
        windowIndex: 0,
        paneId: 'stale-p1',
      );
      await tester.pump();

      // 注入した状態が本当に複数ペイン（panes.length > 1）であることを確認
      // （ガードなしなら _buildPaneIndicator は表示される条件を満たす）。
      final staleState = container.read(tmuxProvider);
      expect(staleState.activeWindow?.panes.length, 2);

      // ガード: read-only では pane indicator は描画されない
      expect(paneIndicatorPainter(), findsNothing);

      // mutation（select/split/kill-pane 等の tmux コマンド）は一切発行されない
      expect(
        client.execCommands.any((c) => c.contains('select-pane')),
        isFalse,
      );
      expect(
        client.execCommands.any(
          (c) => c.contains('split-window') || c.contains('kill-pane'),
        ),
        isFalse,
      );
    });

    testWidgets('M2 regression: tmux (非 read-only) では pane indicator が表示される', (
      tester,
    ) async {
      // tmux backend（readOnly: false）: kFullTreeOutput の mysession/shell は
      // pane %0/%1 の 2 ペインを持つため indicator が描画される。
      await TerminalTestScaffold.pumpTerminalScreen(tester);
      expect(paneIndicatorPainter(), findsWidgets);
    });
  });

  group('TerminalScreen herdr mutation enabled (T13)', () {
    testWidgets(
      'mutation UI is enabled without readOnly: SpecialKeysBar shown, '
      'no READ ONLY banner',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        // Q-02/T13: herdr でも mutation UI が有効化される（readOnly 明示時のみ
        // read-only バナー。H6 の opt-in は存続）。
        expect(find.byType(SpecialKeysBar), findsOneWidget);
        expect(find.text('READ ONLY — viewing only'), findsNothing);

        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets(
      'special key tap routes accepted keys via PaneKeyMap to send-keys '
      '(Q-07 ①)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        // ESC（受理キー）→ `herdr pane send-keys w1:p1 Escape`
        await tester.tap(find.text('ESC'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr pane send-keys w1:p1 Escape',
          ),
          isTrue,
          reason: '受理キー（ESC）は PaneKeyMap 経由で send-keys に送られること',
        );

        // キーオーバーレイの 1500ms タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 1500));
      },
    );

    testWidgets(
      'special key tap routes rejected keys via PaneKeyMap to send-text '
      'escape (Q-07 ②)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        // PgUp（拒否キー）→ `herdr pane send-text w1:p1` + `\x1b[5~`
        await tester.tap(find.text('PgUp'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          client.execCommands.any(
            (c) =>
                c.startsWith('herdr pane send-text w1:p1') &&
                c.contains('\x1b[5~'),
          ),
          isTrue,
          reason: '拒否キー（PgUp）は send-text でエスケープシーケンスが送られること',
        );

        await tester.pump(const Duration(milliseconds: 1500));
      },
    );

    testWidgets(
      'special key tap routes control characters via PaneKeyMap to send-text '
      '(Q-07 ③)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        // C-d（制御文字）→ `herdr pane send-text w1:p1` + 0x04
        // （`sendSpecialKeyForTesting` は SpecialKeysBar のタップが最終的に
        // 到達する `_sendSpecialKeyWithOverlay` → `_sendSpecialKey` と同じ経路）。
        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.sendSpecialKeyForTesting('C-d');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          client.execCommands.any(
            (c) =>
                c.startsWith('herdr pane send-text w1:p1') &&
                c.codeUnits.contains(0x04),
          ),
          isTrue,
          reason: '制御文字（C-d）は send-text で制御文字そのものが送られること',
        );

        await tester.pump(const Duration(milliseconds: 1500));
      },
    );

    testWidgets(
      'defensive invalid_key notification is shown when send-keys rejects a key',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          // send-keys が未知キー名を `invalid_key` で拒否する（防御的経路・R9）。
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
            'herdr pane send-keys w1:p1 UnknownKey123':
                '{"error":{"code":"invalid_key","message":"unsupported key"}}',
          },
          execExitCodes: {'herdr pane send-keys w1:p1 UnknownKey123': 1},
          settle: false,
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.sendSpecialKeyForTesting('UnknownKey123');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.text('このキーは herdr で送信できませんでした'),
          findsOneWidget,
          reason: 'invalid_key は防御的に SnackBar 通知されること',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );
  });

  group('TerminalScreen herdr AutoFit (bug1)', () {
    testWidgets(
      'layout の pane rect から paneWidth が解決され AutoFit に反映される',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        // ポーリングで snapshot cache の layout rect（120x24）が解決され、
        // _viewNotifier の paneWidth / paneHeight が更新される。
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));

        final terminal = tester.widget<AnsiTextView>(
          find.byType(AnsiTextView),
        );
        expect(
          terminal.paneWidth,
          120,
          reason: 'herdr の snapshot layout rect から paneWidth が解決されること',
        );
        expect(
          terminal.paneHeight,
          24,
          reason: 'herdr の snapshot layout rect から paneHeight が解決されること',
        );
      },
    );

    testWidgets(
      'zoom 中は pane rect でなく layout.area（タブ全面）の幅で AutoFit が計算される',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotZoomedFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));

        final terminal = tester.widget<AnsiTextView>(
          find.byType(AnsiTextView),
        );
        // pane rect は非 zoom 値（width 40）だが、表示はタブ全面（area 120）。
        expect(
          terminal.paneWidth,
          120,
          reason: 'zoom 中は pane rect でなく layout.area の幅が使われること',
        );
      },
    );

    testWidgets(
      'layout が無い（rect 取得不能）場合は既定 80 のまま（spec.md:75 フォールバック）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));

        final terminal = tester.widget<AnsiTextView>(
          find.byType(AnsiTextView),
        );
        // _viewNotifier の既定値は paneWidth 80（_TerminalViewData 既定）。
        expect(
          terminal.paneWidth,
          80,
          reason: 'rect 取得不能時は既定 80 幅で AutoFit が計算される',
        );
      },
    );
  });

  group('TerminalScreen herdr セレクタ再タップガード (bug3)', () {
    testWidgets(
      'セレクタ開手中の再タップは無視され、シートが多重起動しない',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          execOutputs: {
            'herdr api snapshot': kHerdrTwoWorkspaceSnapshotFixture,
            'herdr pane read w1:p1': 'content from p1\n',
            'herdr pane read w2:p1': 'content from p2\n',
          },
          settle: false,
        );

        // workspace セグメント（lab-ws1）を連続タップ。
        // 1回目のタップで _herdrSelectorOpening=true になり、2回目以降は
        // ガードで無視される（シートが多重起動しない・バグ3）。
        await tester.tap(find.text('lab-ws1'));
        await tester.tap(find.text('lab-ws1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // シートは1つだけ表示される（多重起動しない・バグ3）。
        expect(find.text('Select Session'), findsOneWidget);

        // シートを閉じるとフラグがリセットされ、再度開ける。
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('lab-ws1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Session'), findsOneWidget,
            reason: 'シートを閉じた後は再度セレクタを開けること');
      },
    );
  });

  group('TerminalScreen herdr スクロールバック (bug4)', () {
    testWidgets(
      '深い履歴の要求行数はユーザー設定 scrollbackLines と整合する',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          settings: const AppSettings(
            keepScreenOn: false,
            scrollbackLines: 2000,
          ),
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
            'herdr pane read w1:p1 --source recent --lines 2000 --raw':
                'deep-0\ndeep-1\n',
          },
          settle: false,
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.loadHistoryForScrollForTesting();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          client.execCommands.any(
            (c) =>
                c.contains('herdr pane read w1:p1 --source recent') &&
                c.contains('--lines 2000'),
          ),
          isTrue,
          reason: 'バグ4: herdr の深い履歴は scrollbackLines（2000）で要求されること',
        );
      },
    );

    testWidgets(
      'scrollbackLines が最小値未満でもクランプされ、最大値超過でもクランプされる',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          readOnly: true,
          // 20000 超過（例: 99999）→ クランプして 20000 で要求される。
          settings: const AppSettings(
            keepScreenOn: false,
            scrollbackLines: 99999,
          ),
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
            'herdr pane read w1:p1 --source recent --lines 20000 --raw':
                'deep-0\ndeep-1\n',
          },
          settle: false,
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.loadHistoryForScrollForTesting();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          client.execCommands.any(
            (c) =>
                c.contains('herdr pane read w1:p1 --source recent') &&
                c.contains('--lines 20000'),
          ),
          isTrue,
          reason: 'バグ4: scrollbackLines は [200, 20000] にクランプされること',
        );
      },
    );
  });
}
