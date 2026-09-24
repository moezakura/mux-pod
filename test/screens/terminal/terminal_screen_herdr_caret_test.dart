import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot_reader.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

class _FakeHerdrCaretReader implements HerdrCaretSnapshotReader {
  _FakeHerdrCaretReader({this.snapshotOf});

  /// pane ID → caret snapshot（null は取得失敗）。
  final HerdrCaretSnapshot? Function(String paneId)? snapshotOf;

  /// [read] の呼び出し回数。
  int calls = 0;

  @override
  Future<HerdrCaretSnapshot?> read({
    required String paneId,
    required int cols,
    required int rows,
  }) async {
    calls++;
    return snapshotOf?.call(paneId);
  }
}

/// caret snapshot の簡易コンストラクタ（既定 frame は layout fixture の 120x24）。
HerdrCaretSnapshot _caretAt({
  int? x = 5,
  int? y = 0,
  bool visible = true,
  String paneId = 'w1:p1',
  int frameWidth = 120,
  int frameHeight = 24,
}) => HerdrCaretSnapshot(
  x: x,
  y: y,
  visible: visible,
  shape: 1,
  frameWidth: frameWidth,
  frameHeight: frameHeight,
  protocolVersion: 17,
  paneId: paneId,
  capturedAt: DateTime(2025, 1, 1),
);

/// AnsiTextView 内に描画された MuxPod 側カーソル（caret span の ColoredBox）。
Finder inTextViewCaret() => find.descendant(
  of: find.byType(AnsiTextView),
  matching: find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == DesignColors.primary,
  ),
);

/// caret は 500ms 周期で点滅するため、存在検証は ON 相で行う。
/// 直近の相で見つからなければ 600ms 進めて ON 相で再確認する。
/// 戻り値: いずれかの相で描画されていたら true。
Future<bool> caretSeen(WidgetTester tester) async {
  if (tester.any(inTextViewCaret())) return true;
  await tester.pump(const Duration(milliseconds: 600));
  return tester.any(inTextViewCaret());
}

void main() {
  group('TerminalScreen herdr caret (Phase 4)', () {
    // caret テスト共通の settings（実験フラグ ON・カーソル表示 ON）。
    const caretOnSettings = AppSettings(
      keepScreenOn: false,
      experimentalHerdrCaretPositionEnabled: true,
      adjustMode: 'manual',
      fontSize: 14.0,
    );

    testWidgets('設定OFF時は caret reader が呼ばれず helper wire も 0 回', (tester) async {
      // 注入フェイクを渡しても、設定 OFF（既定）では呼び出し・副作用とも
      // 一切起きない（enabled ゲート）。production manager（uname/sha256sum/
      // helper 実行）も構築されないため wire 呼び出しは 0 回。
      final caretReader = _FakeHerdrCaretReader(snapshotOf: (_) => _caretAt());
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        // 設定 OFF（既定）で実験フラグは false。
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        herdrCaretReader: caretReader,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(caretReader.calls, 0, reason: '設定 OFF では caret reader が呼ばれないこと');

      // helper wire（uname / sha256sum / helper 実行 / chmod / status）が
      // 一切実行されないこと（OFF 時の追加副作用ゼロ）。
      expect(
        client.execCommands.any(
          (c) =>
              c.contains('uname') ||
              c.contains('sha256sum') ||
              c.contains('herdr-caret-helper') ||
              c.contains('chmod') ||
              c.contains('herdr status'),
        ),
        isFalse,
        reason: '設定 OFF では caret helper 関連の wire 呼び出しが 0 回であること',
      );

      // 見た目（従来挙動）は同一: 通常の pane 内容が表示される。
      expect(find.textContaining('content'), findsWidgets);
    });

    testWidgets('caret 成功時は初回スクロール先が caret 位置になる', (tester) async {
      // 300 行の履歴 + 150 行 pane。caret y=0（可視フレーム最上段）なら
      // scrollToCaret は中央寄せで内容中央付近へ、末尾フォールバック
      // （scrollToBottom）とは明確に異なる位置へスクロールする。
      final caretReader = _FakeHerdrCaretReader(
        snapshotOf: (_) =>
            _caretAt(x: 5, y: 0, frameWidth: 120, frameHeight: 150),
      );
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        settings: caretOnSettings,
        execOutputs: {
          'herdr api snapshot': kHerdrTallLayoutSnapshotFixture,
          'herdr pane read': List.generate(300, (i) => 'content-$i').join('\n'),
        },
        herdrCaretReader: caretReader,
        settle: false,
      );
      expect(
        caretReader.calls,
        greaterThan(0),
        reason: '設定 ON では caret reader が呼ばれること',
      );

      // 初回コンテンツ受信（_applyUpdate → _scrollToCaret → 100ms遅延）
      await tester.pump(const Duration(milliseconds: 100));
      // scrollToCaret の animateTo(300ms) を消化
      await tester.pump(const Duration(milliseconds: 500));

      final scrollable = find.descendant(
        of: find.byType(AnsiTextView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'コンテンツがビューポートを超えスクロール可能な状態であること',
      );
      expect(
        position.pixels,
        greaterThan(0),
        reason: 'caret 位置へスクロールしたが左上（先頭）には飛ばないこと',
      );
      expect(
        position.pixels,
        lessThan(position.maxScrollExtent * 0.9),
        reason: 'caret 成功時は末尾ではなく caret 位置（中央寄せ）へスクロールすること',
      );

      // 可視 caret は（blink ON 相で）描画される。
      expect(await caretSeen(tester), isTrue, reason: '可視 caret が描画されること');
    });

    testWidgets('visible=false（cursor:null 観測）ではカーソルを描画しない', (tester) async {
      // visible=false / 位置不明のケース: 従来の cursorX/cursorY（0,0 固定）へ
      // フォールバックせず、MuxPod 側カーソルは描画されない。
      final caretReader = _FakeHerdrCaretReader(
        snapshotOf: (_) => _caretAt(x: null, y: null, visible: false),
      );
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        settings: caretOnSettings,
        execOutputs: {
          'herdr api snapshot': kHerdrLargeLayoutSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        herdrCaretReader: caretReader,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      // blink の ON/OFF 両相で描画されないことを確認する。
      expect(
        inTextViewCaret(),
        findsNothing,
        reason: 'visible=false ではカーソルを描画しないこと',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        inTextViewCaret(),
        findsNothing,
        reason: 'visible=false ではカーソルを描画しないこと（blink ON 相）',
      );
    });

    testWidgets('caret 取得失敗時は末尾フォールバック（scrollToBottom）', (tester) async {
      // reader が null（取得失敗・非対応環境）を返す場合は従来どおり末尾。
      // （caret 成功テストと同じ tall fixture / 300 行で末尾へ落ちることを確認）
      final caretReader = _FakeHerdrCaretReader(snapshotOf: (_) => null);
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        settings: caretOnSettings,
        execOutputs: {
          'herdr api snapshot': kHerdrTallLayoutSnapshotFixture,
          'herdr pane read': List.generate(300, (i) => 'content-$i').join('\n'),
        },
        herdrCaretReader: caretReader,
        settle: false,
      );

      await tester.pump(const Duration(milliseconds: 100));
      // scrollToBottom の animateTo(300ms) を消化
      await tester.pump(const Duration(milliseconds: 500));

      final scrollable = find.descendant(
        of: find.byType(AnsiTextView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'コンテンツがビューポートを超えスクロール可能な状態であること',
      );
      expect(
        position.pixels,
        closeTo(position.maxScrollExtent, 1.0),
        reason: '取得失敗時は末尾（scrollToBottom 相当）へフォールバックすること',
      );
    });

    testWidgets('pane 切替後は旧 pane の caret を表示しない', (tester) async {
      // w1:p1 は可視 caret、w1:p2 は取得失敗（null）のフェイク。
      final caretReader = _FakeHerdrCaretReader(
        snapshotOf: (paneId) => paneId == 'w1:p1' ? _caretAt(x: 5, y: 0) : null,
      );
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        settings: caretOnSettings,
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        herdrCaretReader: caretReader,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 切替前: w1:p1 の caret が（blink ON 相で）描画されている。
      expect(
        await caretSeen(tester),
        isTrue,
        reason: '切替前は w1:p1 の caret が描画されること',
      );

      // pane 切替（表示対象を w1:p2 へ）。画面側は表示中 paneId とフレームの
      // 同一性（_isCurrentHerdrTarget）を照合し、旧 pane の caret を破棄する。
      final dynamic state = tester.state(find.byType(TerminalScreen));
      state.switchHerdrTargetForTesting('w1:p2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      // blink の ON/OFF 両相で旧 caret は描画されない。
      expect(
        inTextViewCaret(),
        findsNothing,
        reason: 'pane 切替後は旧 pane の caret を表示しないこと',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        inTextViewCaret(),
        findsNothing,
        reason: 'pane 切替後は旧 pane の caret を表示しないこと（blink ON 相）',
      );
      // w1:p2 の内容は表示され続ける（caret 失敗は表示に影響しない）。
      expect(find.textContaining('content'), findsWidgets);
    });

    // 既存「Herdr は末尾へスクロール」テストは設定 OFF（既定）の回帰として
    // 上記「初回コンテンツ受信時は末尾アライン」で維持される。
  });
}
