import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_content_reader.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_read.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/widgets/scroll_to_bottom_button.dart';

import '../../helpers/terminal_test_scaffold.dart';

// G4 実測のスナップショット fixture（workspace label は lab-ws1 / pane は w1:p1）。
// ターミナルというより画面の前提として target 解決にのみ使う。
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

/// ポーリング応答をスクリプト制御する reader（既存 epoch テストの踏襲）。
class _ScriptedHerdrPaneContentReader implements PaneContentReader {
  String pollContent = '';

  @override
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request) async {
    if (request.purpose == PaneReadPurpose.scrollback) {
      return MultiplexerPaneSnapshot(content: pollContent);
    }
    return MultiplexerPaneSnapshot(content: pollContent);
  }
}

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

/// 固定フォント設定（fontSize 10・adjustMode none → lineHeight = 12px）。
const _kFixedFontSettings = AppSettings(
  keepScreenOn: false,
  adjustMode: 'none',
  fontSize: 10.0,
);

String _lines(int n) => List.generate(n, (i) => 'line $i').join('\n');

/// 横方向にビューポートをはみ出す行（axis フィルタ検証用）。
String _wideLines(int n) => List.generate(n, (i) => 'x' * 200).join('\n');

Finder _verticalTerminalScrollable() => find.descendant(
  of: find.byType(AnsiTextView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

ScrollPosition _scrollPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_verticalTerminalScrollable()).position;

bool _fabLocked(WidgetTester tester) => tester
    .widget<ScrollToBottomButton>(find.byType(ScrollToBottomButton))
    .locked;

/// コンテンツの伸縮を伴うポーリング（適応型ポーリングの上限 2000ms を超える
/// 2500ms を pump して必ず 1 回はポーリングを発火させる・既存 epoch
/// テストと同様）。フレーム後コールバック（followToBottom）の実行分は追加の
/// pump() で消化する。
Future<void> _pumpPoll(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2500));
  await tester.pump();
}

/// FAB タップ/長押しの `scrollToBottom()`（animateTo 300ms）を消化する。
///
/// `scrollToBottom()` は `addPostFrameCallback` を登録するだけでフレームを
/// 予約しないため、テスト側で明示的にフレームを要求する。また Ticker は
/// 最初のフレームで startTime を設定し elapsed=0 になるため、duration 付き
/// pump を 2 回使って経過分を反映させる。
Future<void> _pumpScrollToBottom(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump(); // postFrameCallback → animateTo 開始
  await tester.pump(const Duration(milliseconds: 100)); // 初回ティック（startTime 設定）
  await tester.pump(const Duration(milliseconds: 400)); // 経過 300ms を消化
}

/// 初期表示: 300 行のコンテンツで ListView をスクロール可能にし、
/// 初回 _scrollToCaret（100ms 遅延）→ 末尾アライン（animateTo 300ms）を消化する。
Future<void> _pumpTerminal(
  WidgetTester tester,
  _ScriptedHerdrPaneContentReader reader,
) async {
  await TerminalTestScaffold.pumpTerminalScreen(
    tester,
    connection: _herdrConnection(),
    sessionName: 'lab-ws1',
    initialPaneId: 'w1:p1',
    paneContentReader: reader,
    execOutputs: {'herdr api snapshot': kHerdrSnapshotFixture},
    settings: _kFixedFontSettings,
    settle: false,
  );
  // 初回 _scrollToCaret（100ms 遅延）→ 末尾アライン（animateTo 300ms）を消化。
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

/// 設定メニュー → Select Mode 選択（ライブポーリング中は pumpAndSettle 不可のため手動 pump）。
Future<void> _enterSelectMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Select Mode'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('TerminalScreen follow-scroll (Issue #87 + FAB ロック)', () {
    testWidgets('最下部表示中にコンテンツが伸びると次ポーリング後 offset == maxScrollExtent（自動追従）', (
      tester,
    ) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      final position = _scrollPosition(tester);
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'コンテンツがビューポートを超えスクロール可能な状態であること',
      );
      expect(position.pixels, closeTo(position.maxScrollExtent, 1.0));

      // コンテンツを 300 → 330 行へ伸長 → 次ポーリング後に追従する。
      reader.pollContent = _lines(330);
      await _pumpPoll(tester);

      final after = _scrollPosition(tester);
      expect(
        after.pixels,
        closeTo(after.maxScrollExtent, 1.0),
        reason: '最下部表示中はコンテンツ伸長に追従して maxScrollExtent に到達すること',
      );
    });

    testWidgets('最下部から上へドラッグすると追従をやめる（offset 変化なし）', (tester) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      // 指を下方向へドラッグ（上スクロール = 履歴方向）して最下部を離れる。
      await tester.drag(_verticalTerminalScrollable(), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // 弾性スクロール消化

      final dragged = _scrollPosition(tester);
      expect(
        dragged.pixels,
        lessThan(dragged.maxScrollExtent - 50),
        reason: 'ドラッグで最下部から離れていること',
      );
      final draggedPixels = dragged.pixels;

      // コンテンツ伸長しても追従しない（offset は変わらない）。
      reader.pollContent = _lines(360);
      await _pumpPoll(tester);

      final after = _scrollPosition(tester);
      expect(
        after.pixels,
        closeTo(draggedPixels, 1.0),
        reason: '最下部にいないときはコンテンツ伸長に追従しないこと',
      );
    });

    testWidgets('上部から FAB タップで最下部へ戻り、以後コンテンツ伸長に追従する', (tester) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      // 最下部を離れてから FAB タップで最下部へ戻る。
      await tester.drag(_verticalTerminalScrollable(), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ScrollToBottomButton), findsOneWidget);
      await tester.tap(find.byType(ScrollToBottomButton));
      await _pumpScrollToBottom(tester);

      final position = _scrollPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 1.0));

      // タップ後は追従が有効化される。
      reader.pollContent = _lines(380);
      await _pumpPoll(tester);
      final after = _scrollPosition(tester);
      expect(
        after.pixels,
        closeTo(after.maxScrollExtent, 1.0),
        reason: 'FAB タップで最下部へ戻った後はコンテンツ伸長に追従すること',
      );
    });

    testWidgets('FAB 長押しでロック → 上へドラッグでロック解除 → コンテンツ伸長しても追従しない', (tester) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      // 最下部を離れてから FAB 長押しで最下部ロック。
      await tester.drag(_verticalTerminalScrollable(), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.longPress(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(
        _fabLocked(tester),
        isTrue,
        reason: '長押しで locked prop が true になること',
      );
      await tester.pump(const Duration(milliseconds: 400)); // scrollToBottom 消化
      expect(
        _scrollPosition(tester).pixels,
        closeTo(_scrollPosition(tester).maxScrollExtent, 1.0),
        reason: 'ロック時に最下部へスクロールすること',
      );

      // 上へドラッグ（履歴方向）で手動スクロール → ロック解除。
      await tester.drag(_verticalTerminalScrollable(), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_fabLocked(tester), isFalse, reason: '手動スクロールでロックが解除されること');
      final draggedPixels = _scrollPosition(tester).pixels;

      // ロック解除後はコンテンツ伸長しても追従しない。
      reader.pollContent = _lines(400);
      await _pumpPoll(tester);
      expect(
        _scrollPosition(tester).pixels,
        closeTo(draggedPixels, 1.0),
        reason: 'ロック解除後はコンテンツ伸長に追従しないこと',
      );
    });

    testWidgets('ロック中に FAB タップするとロック解除のみ（スクロール位置は変わらない）', (tester) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      await tester.longPress(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(_fabLocked(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 400)); // scrollToBottom 消化

      final before = _scrollPosition(tester).pixels;
      await tester.tap(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(
        _fabLocked(tester),
        isFalse,
        reason: 'ロック中タップで locked が false に戻ること',
      );
      expect(
        _scrollPosition(tester).pixels,
        closeTo(before, 1.0),
        reason: 'ロック中タップではスクロール位置が変わらないこと',
      );
    });

    testWidgets('ロック中に select モードへ遷移するとロックが解除される', (tester) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      await tester.longPress(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(_fabLocked(tester), isTrue);

      await _enterSelectMode(tester);
      expect(_fabLocked(tester), isFalse, reason: 'モード遷移（select）でロックが解除されること');
    });

    testWidgets('ロック中に scrollSend モードへ遷移するとロックが解除される', (tester) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      await tester.longPress(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(_fabLocked(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Scroll Send Mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _fabLocked(tester),
        isFalse,
        reason: 'モード遷移（scrollSend）でロックが解除されること',
      );
    });

    testWidgets('横方向のドラッグではロックが解除されない（axis フィルタ）', (tester) async {
      // 横にはみ出す行で horizontal SingleChildScrollView を存在させる。
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _wideLines(300);
      await _pumpTerminal(tester, reader);

      await tester.longPress(find.byType(ScrollToBottomButton));
      await tester.pump();
      expect(_fabLocked(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 400));

      // 純横方向ドラッグ: horizontal ScrollView の通知（dragDetails 付き）が
      // NotificationListener へバブリングするが、axis フィルタで無視される。
      await tester.drag(_verticalTerminalScrollable(), const Offset(-200, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        _fabLocked(tester),
        isTrue,
        reason: '横スクロールは「自分でスクロール」に含めずロックを維持すること',
      );
    });

    testWidgets('FAB タップのアニメ中にコンテンツが伸びてもタップ後の追従が無効化されない', (tester) async {
      final reader = _ScriptedHerdrPaneContentReader()
        ..pollContent = _lines(300);
      await _pumpTerminal(tester, reader);

      // 最下部を離れる。
      await tester.drag(_verticalTerminalScrollable(), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // FAB タップ → animateTo（300ms）開始。
      await tester.tap(find.byType(ScrollToBottomButton));
      tester.binding.scheduleFrame();
      await tester.pump(); // postFrameCallback → animateTo 開始

      // アニメ完了前に Enter キー送信（ポーリングブースト・50ms）→
      // アニメ中にポーリングが発火してコンテンツが伸びる
      // （Issue #87 の「最下部で Enter → 新しい行へ追従」シナリオ）。
      reader.pollContent = _lines(340);
      await tester.tap(find.byIcon(Icons.keyboard_return));
      await tester.pump(const Duration(milliseconds: 100)); // ブーストポーリング発火
      await tester.pump(); // followToBottom（postFrame）実行
      await tester.pump(const Duration(milliseconds: 400)); // animateTo 残りを消化

      final position = _scrollPosition(tester);
      expect(
        position.pixels,
        closeTo(position.maxScrollExtent, 1.0),
        reason: 'アニメ中のコンテンツ伸長にも追従して最下部に到達すること',
      );

      // タップによる追従がその後も有効（中間通知でピンが false 化していない）。
      reader.pollContent = _lines(380);
      await _pumpPoll(tester);
      final after = _scrollPosition(tester);
      expect(
        after.pixels,
        closeTo(after.maxScrollExtent, 1.0),
        reason: 'タップ後の追従がアニメ中の競合で失われていないこと',
      );
    });
  });
}
