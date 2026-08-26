import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_content_reader.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_read.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';

import '../../helpers/terminal_test_scaffold.dart';

// G4 実測のスナップショット fixture（workspace label は lab-ws1 / pane は w1:p1）。
// 再解決で同じ pane（w1:p1）に解決されるため、切替コミットなしでエポックだけ
// 増えるシナリオ（A3改・エポック照合の epoch 成分）を作れる。
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

List<String> _switchEvents(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(TerminalScreen));
  return List<String>.from(state.herdrSwitchEventsForTesting());
}

/// w1:p1 の read を [gate] で保留する reader（in-flight ウィンドウの再現）。
///
/// 保留中に表示対象が変わると、await 完了時のエポック照合で結果が破棄される
/// ことを検証するために使う（A3改・paneId 成分）。
class _GatedHerdrPaneContentReader implements PaneContentReader {
  _GatedHerdrPaneContentReader(this.gate);

  /// w1:p1 の read はこの gate で保留される。
  final Completer<MultiplexerPaneSnapshot> gate;

  /// read が要求された pane ID の記録（検証用）。
  final List<String> requestedPaneIds = [];

  @override
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request) async {
    requestedPaneIds.add(request.paneId);
    if (request.paneId == 'w1:p1') return gate.future;
    return const MultiplexerPaneSnapshot(content: 'fresh p2 content\n');
  }
}

/// ポーリング / スクロールバックの応答をスクリプト制御する reader。
///
/// - ライブ read（[PaneReadPurpose.live]）は [pollContent] を返す。
/// - スクロールバック read（[PaneReadPurpose.scrollback]）は [deepContent] を返す。
/// - [gate] が非 null のとき、次のライブ read を 1 回だけ保留する
///   （バッファ書き込みを確定させる in-flight ウィンドウ）。
/// - [failNextPoll] が true のとき、次のライブ read を
///   target-not-found で失敗させる（再解決 = 強制再取得 → エポック++ のトリガ）。
class _ScriptedHerdrPaneContentReader implements PaneContentReader {
  String pollContent = 'live-1\n';
  String deepContent = 'deep-1\n';
  bool failNextPoll = false;
  Completer<void>? gate;

  @override
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request) async {
    // スクロールバックはライブとは別応答（read intent で識別・バグ4 根本対応）。
    if (request.purpose == PaneReadPurpose.scrollback) {
      return MultiplexerPaneSnapshot(content: deepContent);
    }
    final g = gate;
    if (g != null) {
      gate = null; // one-shot
      await g.future;
    }
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

/// スクロールバック read を [gate] で保留する reader（_loadHistoryForScroll の破棄検証用）。
class _GatedDeepHistoryReader implements PaneContentReader {
  _GatedDeepHistoryReader(this.gate);

  final Completer<MultiplexerPaneSnapshot> gate;
  bool failNextPoll = false;
  final String pollContent = 'live-1\n';

  @override
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request) async {
    // スクロールバック read（read intent で識別）。
    if (request.purpose == PaneReadPurpose.scrollback) return gate.future;
    if (failNextPoll) {
      failNextPoll = false;
      throw const HerdrTargetNotFoundException(
        kind: HerdrTargetNotFoundKind.pane,
        message: 'no such pane',
        errorCode: 'pane_not_found',
        exitCode: 1,
      );
    }
    return const MultiplexerPaneSnapshot(content: 'live-1\n');
  }
}

/// 設定メニュー（設定アイコン → モード切替）で選択（select）モードへ入る。
///
/// ライブポーリングが動く間は pumpAndSettle が終わらないため、手動 pump で
/// ボトムシートのアニメーションを進める。
Future<void> _enterSelectMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Select Mode'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('TerminalScreen herdr epoch matching (A3改)', () {
    testWidgets(
      'poll discards an in-flight read whose target changed during the await '
      '(cache epoch + currentPaneId)',
      (tester) async {
        final gate = Completer<MultiplexerPaneSnapshot>();
        final reader = _GatedHerdrPaneContentReader(gate);

        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          initialPaneId: 'w1:p1',
          paneContentReader: reader,
          execOutputs: {'herdr api snapshot': kHerdrSnapshotFixture},
          settle: false,
        );

        // 初回ポーリングが w1:p1 の read で保留されている（in-flight）。
        expect(reader.requestedPaneIds, contains('w1:p1'));

        // 保留中に表示対象を w1:p2 へ切替（切替コミットの単一入口）。
        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.switchHerdrTargetForTesting('w1:p2');
        await tester.pump();

        // 保留していた read を解放 → 照合で paneId 不一致 → 結果は破棄される。
        gate.complete(
          const MultiplexerPaneSnapshot(content: 'stale p1 content\n'),
        );
        await tester.pump();

        // 次のポーリングは新しいターゲット w1:p2 を読む。
        await tester.pump(const Duration(milliseconds: 150));

        expect(
          find.textContaining('fresh p2 content'),
          findsWidgets,
          reason: '切替後のターゲット内容が表示されること',
        );
        expect(
          find.textContaining('stale p1 content'),
          findsNothing,
          reason: 'await 中にターゲットが変わった in-flight read は破棄されること',
        );
      },
    );

    testWidgets(
      'buffered update is discarded when the epoch changed during scroll mode '
      '(re-resolve to the same pane)',
      (tester) async {
        final reader = _ScriptedHerdrPaneContentReader();

        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          initialPaneId: 'w1:p1',
          paneContentReader: reader,
          execOutputs: {'herdr api snapshot': kHerdrSnapshotFixture},
          settle: false,
        );

        // 初回ポーリングの内容が表示される。
        expect(find.textContaining('live-1'), findsWidgets);

        // スクロールモードへ（深い履歴 deep-1 が適用される）。
        await _enterSelectMode(tester);
        expect(find.textContaining('deep-1'), findsWidgets);

        // 次のポーリング read を gate してから、バッファ内容へ差し替え。
        // 2500ms は適応型ポーリングの上限（2000ms）を超えるため、必ず
        // 1 回はポーリングが発火して read が in-flight になる。
        reader.pollContent = 'buffered-content\n';
        final gate = Completer<void>();
        reader.gate = gate;
        await tester.pump(const Duration(milliseconds: 2500));
        gate.complete();
        await tester.pump();

        // in-flight read が完了 → スクロールモード中なのでバッファされる
        // （表示対象同一性はエポック 0 で記録される）。
        expect(find.textContaining('buffered-content'), findsNothing);

        // 次のポーリングを target-not-found で失敗 → 強制再取得 → エポック++
        // （同 pane に再解決されるため切替は発生せず、バッファは保持される）。
        // 間隔は 50ms（内容変化でリセット済み）のため 90ms で十分。
        reader.failNextPoll = true;
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          _switchEvents(tester).any((e) => e.contains('re-resolve succeeded')),
          isTrue,
          reason: '再解決（エポック++）が発生していること',
        );

        // 再解決後のポーリング内容を差し替え（破棄された内容の再適用を防ぐ）。
        reader.pollContent = 'post-resolve\n';

        // スクロールモード解除 → バッファ適用時にエポック不一致 → 破棄。
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        expect(
          find.textContaining('buffered-content'),
          findsNothing,
          reason: 'エポックが変わったバッファ内容は適用されないこと',
        );

        await tester.pump(const Duration(milliseconds: 150));
        expect(
          find.textContaining('post-resolve'),
          findsWidgets,
          reason: '破棄後は次回ポーリングの新しい内容が表示されること',
        );
      },
    );

    testWidgets(
      'deep history read is discarded when the epoch changed during the await',
      (tester) async {
        final gate = Completer<MultiplexerPaneSnapshot>();
        final reader = _GatedDeepHistoryReader(gate);

        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: _herdrConnection(),
          sessionName: 'lab-ws1',
          initialPaneId: 'w1:p1',
          paneContentReader: reader,
          execOutputs: {'herdr api snapshot': kHerdrSnapshotFixture},
          settle: false,
        );

        // スクロールモードへ → 深い履歴 read がゲートで保留される。
        await _enterSelectMode(tester);

        // 保留中にポーリングを失敗させて再解決（エポック++・同 pane・切替なし）。
        // 2500ms はポーリング間隔の上限（2000ms）を超えるため必ず発火する。
        reader.failNextPoll = true;
        await tester.pump(const Duration(milliseconds: 2500));
        expect(
          _switchEvents(tester).any((e) => e.contains('re-resolve succeeded')),
          isTrue,
          reason: '再解決（エポック++）が発生していること',
        );

        // 深い履歴を解放 → 照合でエポック不一致 → 破棄される。
        gate.complete(
          const MultiplexerPaneSnapshot(content: 'stale deep content\n'),
        );
        await tester.pump();

        expect(
          find.textContaining('stale deep content'),
          findsNothing,
          reason: 'await 中にエポックが変わった深い履歴は適用されないこと',
        );
        expect(
          find.textContaining('live-1'),
          findsWidgets,
          reason: '破棄後はライブ表示が維持されること',
        );
      },
    );
  });
}
