import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart'
    show PaneHyperlink, PaneHyperlinkRange, PaneHyperlinks;
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart'
    show HerdrStatus;
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart'
    show
        HerdrScrollbackLinkHelperRunner,
        ScrollbackLinksResult,
        ScrollbackLinkRestore,
        ScrollbackLinkWindow;
import 'package:flutter_muxpod/theme/design_colors.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';
import 'helpers/scroll_send_test_helpers.dart' show enterMode, mode;

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

/// テスト用: 通常表示のハイパーリンク reader（herdr OSC 8 ハイパーリンク
/// 実験機能）。[_FakeHerdrCaretReader] と同型。
class _FakeHerdrHyperlinkReader implements HerdrHyperlinkReader {
  _FakeHerdrHyperlinkReader({this.linksOf});

  /// pane ID → hyperlinks（null は取得失敗/未対応）。呼ぶたびに再評価される。
  final PaneHyperlinks? Function(String paneId)? linksOf;

  /// [read] の呼び出し回数。
  int calls = 0;

  @override
  Future<PaneHyperlinks?> read({
    required String paneId,
    required int cols,
    required int rows,
  }) async {
    calls++;
    return linksOf?.call(paneId);
  }
}

/// 単一リンクの [PaneHyperlinks] の簡易コンストラクタ。
PaneHyperlinks _linksWithUrl(
  String url, {
  int frameWidth = 120,
  int frameHeight = 24,
}) => PaneHyperlinks(
  frameWidth: frameWidth,
  frameHeight: frameHeight,
  links: [
    PaneHyperlink(
      url: url,
      ranges: const [PaneHyperlinkRange(row: 0, startCol: 0, endCol: 3)],
    ),
  ],
);

/// [HerdrScrollbackLinkHelperRunner] の fake。呼び出し引数
/// （pane/cols/offsets）を記録する。アライン（本文行との対応づけ）成否は
/// このテストの検証対象外のため、返す窓のリンクは常に空にする
/// （widget テストで確認するのは「fake runner が受け取った引数」と
/// 「bodyLinesFor が空でない実際の本文を渡していること」の2点）。
class _FakeScrollbackLinkRunner implements HerdrScrollbackLinkHelperRunner {
  int calls = 0;
  String? lastPaneId;
  int? lastCols;
  List<int>? lastOffsetsFromBottom;

  @override
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  }) async {
    calls++;
    lastPaneId = paneId;
    lastCols = cols;
    lastOffsetsFromBottom = offsetsFromBottom;
    return ScrollbackLinksResult(
      windows: [
        for (final offset in offsetsFromBottom)
          ScrollbackLinkWindow(
            requestedOffset: offset,
            actualOffset: offset,
            hyperlinks: PaneHyperlinks(frameWidth: cols, frameHeight: 0),
          ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
  }
}

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

    // hyperlinks 実験フラグのみ ON（caret は既定 OFF）。status 取得の共有ゲートのテスト用。
    const hyperlinksOnSettings = AppSettings(
      keepScreenOn: false,
      experimentalHerdrHyperlinksEnabled: true,
      adjustMode: 'manual',
      fontSize: 14.0,
    );

    // caret・hyperlinks 両方 ON。両方 ON でも SSH 1 回になることのテスト用。
    const bothOnSettings = AppSettings(
      keepScreenOn: false,
      experimentalHerdrCaretPositionEnabled: true,
      experimentalHerdrHyperlinksEnabled: true,
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

    group('herdr status 取得の共有ゲート（herdr OSC 8 ハイパーリンク実験機能）', () {
      testWidgets('caret・hyperlinks とも OFF（既定）では status 取得の SSH が 0 回', (
        tester,
      ) async {
        // 既存の caret テストと同じ既定設定（両フラグ OFF）で、
        // hyperlinks 側の新規ゲート（_ensureStatusForHyperlinksIfNeeded）が
        // 追加の SSH 実行を発生させないことを固定する回帰テスト。
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.any((c) => c.contains('herdr status')),
          isFalse,
          reason: 'caret・hyperlinks とも OFF の間は status 取得の SSH が 0 回であること',
        );
      });

      testWidgets('hyperlinks ON・caret OFF でも status 取得を single-flight で1回行う', (
        tester,
      ) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.where((c) => c.contains('herdr status')).length,
          1,
          reason:
              'hyperlinks ON なら caret が OFF でも status 取得（HerdrCaretComposer.'
              'ensureStatus の single-flight）が1回走ること',
        );
      });

      testWidgets('caret・hyperlinks とも ON でも status 取得は1回にまとまる', (
        tester,
      ) async {
        // setupProduction（caret 側）と hyperlinks 側の起動が同じ
        // HerdrCaretComposer.ensureStatus の single-flight を通るため、
        // 両方 ON でも herdr status の SSH 実行は重複しない。
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: bothOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          client.execCommands.where((c) => c.contains('herdr status')).length,
          1,
          reason: 'caret・hyperlinks とも ON でも status 取得の SSH は1回にまとまること',
        );
        // installer 配置確認（uname 等）の共有は、この統合テスト環境では
        // HerdrCaretHelperManifest.load()（rootBundle 経由のアセット読込）が
        // 到達しないため 0 回のまま検証できない（実測: uname -s は 0 回）。
        // installer 共有（ensureInstaller の memo / single-flight）は
        // herdr_caret_composer_test.dart の
        // 「HerdrCaretComposer.ensureInstaller」group で、manifest.load() を
        // 経由しない直接呼び出しにより検証する。
      });
    });

    group('herdr hyperlinks の poll → view 反映', () {
      testWidgets('hyperlinks のみの変化も poll の変更判定に含まれ view へ反映される', (
        tester,
      ) async {
        // 本文・caret は不変のまま hyperlinks だけ変わる poll を模す（変更判定に
        // リンクの同値判定を加えないと、本文が同じでリンクだけ変わった更新が
        // 表示に届かない）。
        var currentUrl = 'https://example.com/a';
        final hyperlinkReader = _FakeHerdrHyperlinkReader(
          linksOf: (_) => _linksWithUrl(currentUrl),
        );
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          herdrHyperlinkReader: hyperlinkReader,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        final dynamic state = tester.state(find.byType(TerminalScreen));
        final PaneHyperlinks? first = state.currentHyperlinksForTesting();
        expect(first, isNotNull, reason: '初回 poll で hyperlinks が反映されること');
        expect(first!.links.single.url, 'https://example.com/a');

        currentUrl = 'https://example.com/b';
        // 適応型ポーリングで間隔が伸びていても次の poll を確実に拾う
        // （AdaptivePollingInterval.maxInterval=2000ms を上回る幅で進める）。
        await tester.pump(const Duration(milliseconds: 2100));

        final PaneHyperlinks? second = state.currentHyperlinksForTesting();
        expect(
          second,
          isNotNull,
          reason: 'hyperlinks のみの変化も poll の変更判定に含まれ view へ反映されること',
        );
        expect(second!.links.single.url, 'https://example.com/b');
      });

      testWidgets('pane 切替後は旧 pane の hyperlinks を表示しない', (tester) async {
        final hyperlinkReader = _FakeHerdrHyperlinkReader(
          linksOf: (paneId) => paneId == 'w1:p1'
              ? _linksWithUrl('https://example.com/p1')
              : null,
        );
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          herdrHyperlinkReader: hyperlinkReader,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        final dynamic state = tester.state(find.byType(TerminalScreen));
        expect(
          state.currentHyperlinksForTesting(),
          isNotNull,
          reason: '切替前は w1:p1 の hyperlinks が反映されていること',
        );

        // pane 切替（herdr_sync.dart の switchTarget → _resetView 経路・
        // caret と同じ identity/generation によるクリア）。
        state.switchHerdrTargetForTesting('w1:p2');
        await tester.pump();

        expect(
          state.currentHyperlinksForTesting(),
          isNull,
          reason: 'pane 切替後は旧 pane の hyperlinks を表示しないこと（_resetView）',
        );

        // 切替直後だけでなく、
        // 切替後に in-flight/pending だった旧 pane 宛ての poll 結果が後から
        // 届いても適用されない（identity/generation の再照合）ことを
        // 確認する。
        await tester.pump(const Duration(milliseconds: 2100));

        expect(
          state.currentHyperlinksForTesting(),
          isNull,
          reason:
              'pane 切替後、時間を進めても旧 pane 宛ての pending な poll 結果が'
              '反映されないこと',
        );
      });

      testWidgets('選択モード中は hyperlinks もバッファされる', (tester) async {
        var currentUrl = 'https://example.com/select-a';
        final hyperlinkReader = _FakeHerdrHyperlinkReader(
          linksOf: (_) => _linksWithUrl(currentUrl),
        );
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          herdrHyperlinkReader: hyperlinkReader,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        final dynamic state = tester.state(find.byType(TerminalScreen));
        final applied = state.currentHyperlinksForTesting();
        expect(applied, isNotNull);
        expect(applied!.links.single.url, 'https://example.com/select-a');

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        expect(
          state.hasBufferedUpdateForTesting(),
          isFalse,
          reason: 'select モード突入直後はバッファが空であること',
        );

        // 選択モード中に hyperlinks だけ変わる poll を模す。
        currentUrl = 'https://example.com/select-b';
        await tester.pump(const Duration(milliseconds: 2100));

        expect(
          state.hasBufferedUpdateForTesting(),
          isTrue,
          reason: '選択モード中の poll はバッファされ、view へ直接反映されないこと',
        );
        final buffered = state.bufferedHyperlinksForTesting();
        expect(buffered, isNotNull, reason: '選択モード中は hyperlinks もバッファされること');
        expect(buffered!.links.single.url, 'https://example.com/select-b');
        expect(
          state.currentHyperlinksForTesting()!.links.single.url,
          'https://example.com/select-a',
          reason: '選択モード中は view へ直接反映されないこと（バッファのみ）',
        );
      });

      testWidgets('本文も hyperlinks も変わらない poll では更新を予約しない', (tester) async {
        final hyperlinkReader = _FakeHerdrHyperlinkReader(
          linksOf: (_) => _linksWithUrl('https://example.com/static'),
        );
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'content\n',
          },
          herdrHyperlinkReader: hyperlinkReader,
          settle: false,
        );
        // 初回反映（content・geometry 確立）を確実に終わらせてから購読する。
        await tester.pump(const Duration(milliseconds: 2100));

        final dynamic state = tester.state(find.byType(TerminalScreen));
        expect(state.currentHyperlinksForTesting(), isNotNull);

        var applyCount = 0;
        final unsubscribe = state.watchViewForTesting(() => applyCount++);
        addTearDown(unsubscribe);
        final callsBefore = hyperlinkReader.calls;

        // 本文・caret・hyperlinks とも不変のまま複数 poll 周期ぶん進める。
        await tester.pump(const Duration(milliseconds: 2100));
        await tester.pump(const Duration(milliseconds: 2100));

        expect(
          applyCount,
          0,
          reason: '本文も hyperlinks も変わらない poll では view 更新を予約しないこと',
        );
        // applyCount=0 が「poll 自体が
        // 止まっていた」による偽の GREEN でないことを、監視期間中に poll が
        // 実際に走ったこと（calls が増えたこと）で確認する。
        expect(
          hyperlinkReader.calls,
          greaterThan(callsBefore),
          reason: '監視期間中も poll 自体は実行され続けていること（内容不変での不予約を検証するため）',
        );
      });
    });

    group('herdr スクロールモードのリンク読取', () {
      testWidgets('select モードでスクロール確定すると fake runner が'
          'pane/cols/offsets 付きで呼ばれ、bodyLinesFor は実際の本文を渡す', (tester) async {
        final runner = _FakeScrollbackLinkRunner();
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': 'hello\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        // AnsiTextView が select モードの内容（herdr pane read の結果）で
        // 再描画され _lastBodyLineTexts が計算されるのを待つ。
        await tester.pump(const Duration(milliseconds: 500));

        final dynamic state = tester.state(find.byType(TerminalScreen));
        final List<String> bodyLines = state
            .scrollbackLinkBodyLinesForTesting();
        expect(
          bodyLines,
          isNotEmpty,
          reason: 'bodyLinesFor が空配列のまま通ってしまう偽の GREEN でないこと',
        );
        expect(
          bodyLines.any((line) => line.contains('hello')),
          isTrue,
          reason: 'bodyLinesFor は表示中の実際の本文（"hello"）を渡していること',
        );

        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);
        // 停止待ち 400ms を超えて進め、往復を発生させる。
        await tester.pump(const Duration(milliseconds: 500));

        // select モード突入自体でも1回自動で往復するため（
        // loadHistoryForScroll）、少なくとも1回は呼ばれていることを見る
        // （厳密に1回であることは検証対象外。往復内容・引数を見る）。
        expect(
          runner.calls,
          greaterThanOrEqualTo(1),
          reason: '停止待ち後に往復が発生していること',
        );
        expect(
          runner.lastPaneId,
          'w1:p1',
          reason: 'currentScrollbackLinkPane() が現在の pane id を渡していること',
        );
        expect(
          runner.lastCols,
          80,
          reason:
              'currentScrollbackLinkPane() が layout rect の幅を渡していること'
              '（kHerdrSnapshotWithLayoutFixture の w1:p1 rect 幅）',
        );
        expect(runner.lastOffsetsFromBottom, isNotNull);
        expect(
          runner.lastOffsetsFromBottom!,
          isNotEmpty,
          reason: '窓（offsetsFromBottom）が計算され runner に渡っていること',
        );
      });

      testWidgets('select モードを抜けると保留中の往復が cancelPending で抑止される', (
        tester,
      ) async {
        final runner = _FakeScrollbackLinkRunner();
        // 1回目と同じ窓を2回目にも要求
        // すると `ScrollbackLinkCache.hasFetched` に弾かれ、endSession の
        // 配線の有無に関わらず往復 0 回になり見分けがつかない。多めの行数
        // を用意し、[jumpToLineFromTopForTesting] で実スクロール位置を
        // 変えることで、2回目は確実に未取得の窓を要求させる。
        //
        // さらに [HerdrScrollbackLinkReader] の開始間隔 2 秒
        // （`minInterval`）ゲートは実時間で判定される（`herdrCacheClock`
        // を渡さない限り）。`tester.pump` は仮想クロックしか進めないため、
        // 偽の時計を注入し pump と同じ幅だけ進める。
        var fakeNow = DateTime(2025, 1, 1);
        final lines = List.generate(500, (i) => 'line$i').join('\n');
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': '$lines\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          herdrCacheClock: () => fakeNow,
          settle: false,
        );

        Future<void> pumpVirtual(Duration d) async {
          fakeNow = fakeNow.add(d);
          await tester.pump(d);
        }

        await pumpVirtual(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        // select モード突入自体の自動往復（loadHistoryForScroll）を
        // 完了させてから基準値を取る。
        await pumpVirtual(const Duration(milliseconds: 500));
        final callsAfterEntry = runner.calls;

        final dynamic state = tester.state(find.byType(TerminalScreen));
        // 実スクロール位置を中間の行へ移し、1回目とは異なる（未取得の）
        // 窓を要求させる。
        state.jumpToLineFromTopForTesting(250);
        await pumpVirtual(const Duration(milliseconds: 1));
        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);

        // 停止待ち 400ms が経つ前（=まだ往復が始まっていない）に select
        // モードを抜ける。TerminalModeController.onModeChanged →
        // root の wiring（select 以外へ遷移）→
        // HerdrScrollbackLinkReader.endSession（cancelPending 含む）を通る。
        // モード変更（applyNormal）は tap ハンドラ内で同期的に発生するため、
        // 400ms の debounce タイマーが発火する前に確実にキャンセルされる。
        await pumpVirtual(const Duration(milliseconds: 100));
        await enterMode(tester, 'Normal Mode');
        expect(mode(tester), TerminalMode.normal);

        // 停止待ち 400ms・開始間隔 2 秒のいずれも越えて進めても、
        // cancelPending 済みの保留は往復として実行されないこと。
        await pumpVirtual(const Duration(milliseconds: 2600));

        expect(
          runner.calls,
          callsAfterEntry,
          reason:
              'select モードを抜けた後は、抜ける直前に予約した保留中の取得が'
              'cancelPending で抑止され、開始間隔 2 秒・停止待ち 400ms を'
              '超えても、未取得の窓への追加の往復が発生しないこと'
              '（endSession/cancelPending の配線）',
        );
      });

      testWidgets('バックグラウンド遷移（AppLifecycleState.paused）で保留中の往復が'
          'cancelPending で抑止される（onPausePolling配線）', (tester) async {
        final runner = _FakeScrollbackLinkRunner();
        // 1回目の往復と同じ窓を2回目にも要求
        // すると `ScrollbackLinkCache.hasFetched` に弾かれ、配線の有無に
        // 関わらず往復 0 回になり見分けがつかない。多めの行数
        // （viewport に収まらない量）を用意し、[jumpToLineFromTopForTesting]
        // で実スクロール位置を変えることで、2回目は確実に未取得の窓を
        // 要求させる。
        //
        // さらに [HerdrScrollbackLinkReader] の開始間隔 2 秒
        // （`minInterval`）ゲートは実時間（`DateTime.now()`）で判定される
        // （clock を渡さない限り）。`tester.pump` が進めるのはタイマー用の
        // 仮想クロックのみで実時間は進まないため、テスト内で1回目に続けて
        // 2回目の往復を発生させるには、`herdrCacheClock` で偽の時計を注入し、
        // pump と同じ幅だけ進める必要がある（注入しないと、配線の有無に
        // 関わらず2回目の往復が永久に起きず見分けがつかない）。
        var fakeNow = DateTime(2025, 1, 1);
        final lines = List.generate(500, (i) => 'line$i').join('\n');
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': '$lines\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          herdrCacheClock: () => fakeNow,
          settle: false,
        );

        Future<void> pumpVirtual(Duration d) async {
          fakeNow = fakeNow.add(d);
          await tester.pump(d);
        }

        await pumpVirtual(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        // select モード突入自体の自動往復（loadHistoryForScroll）を
        // 完了させてから基準値を取る。
        await pumpVirtual(const Duration(milliseconds: 500));
        final callsAfterEntry = runner.calls;

        final dynamic state = tester.state(find.byType(TerminalScreen));
        // 実スクロール位置を中間の行へ移し、1回目とは異なる（未取得の）
        // 窓を要求させる。
        state.jumpToLineFromTopForTesting(250);
        await pumpVirtual(const Duration(milliseconds: 1));
        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);

        // 停止待ち 400ms が経つ前（=まだ往復が始まっていない）にバック
        // グラウンドへ遷移する。_TerminalScreenState.didChangeAppLifecycle
        // State（terminal_screen.dart）の AppLifecycleState.paused 分岐 →
        // SessionLifecycle.pausePolling()（session_lifecycle.dart）の先頭 →
        // env.onPausePolling → HerdrScrollbackLinkReader.cancelPending。
        // didChangeAppLifecycleState の呼び出しは同期的なため、400ms の
        // debounce タイマーが発火する前に確実にキャンセルされる。
        await pumpVirtual(const Duration(milliseconds: 100));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await pumpVirtual(Duration.zero);

        // pausePolling は isActive（
        // `runtime.isInBackground`）を false→true にするだけでも、
        // HerdrScrollbackLinkReader._scheduleOrRunFetch の background-skip
        // により往復 0 回になる。これは cancelPending の配線が無くても
        // 成立してしまうため、配線の有無を見分けられない。400ms が経つ前に
        // resumed へ戻し、isActive を true に戻した状態で待ち時間を進める
        // ことで、cancelPending（配線）の有無だけで結果が分かれるようにする。
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpVirtual(Duration.zero);

        // 停止待ち 400ms・開始間隔 2 秒のいずれも越えて進めても、
        // cancelPending 済みの保留は往復として実行されないこと。
        await pumpVirtual(const Duration(milliseconds: 2600));

        expect(
          runner.calls,
          callsAfterEntry,
          reason:
              'バックグラウンド遷移直前に予約した保留中の取得が'
              'cancelPending で抑止され、resumed 復帰後に isActive が true に'
              '戻り、開始間隔 2 秒・停止待ち 400ms を超えても、未取得の窓への'
              '追加の往復が発生しないこと（onPausePolling の配線）',
        );
      });

      testWidgets('切断操作（Disconnect確認）で保留中の往復が cancelPending で'
          '抑止される（onDisconnect配線）', (tester) async {
        final runner = _FakeScrollbackLinkRunner();
        // 1回目と同じ窓を2回目にも要求すると
        // `ScrollbackLinkCache.hasFetched` に弾かれ、配線の有無に関わらず
        // 往復 0 回になり見分けがつかない。多めの行数を用意し、
        // [jumpToLineFromTopForTesting] で実スクロール位置を変えることで、
        // 2回目は確実に未取得の窓を要求させる。
        //
        // また [HerdrScrollbackLinkReader] の開始間隔 2 秒（`minInterval`）
        // ゲートは実時間（`DateTime.now()`）で判定される（clock を渡さない
        // 限り）。ここでは切断確認ダイアログの Close を押した後、画面が
        // dispose される前の短い実時間の猶予（後述）しかないため、
        // `herdrCacheClock` の偽の時計を先に大きく進めておくことで、
        // 停止待ち 400ms 分の実 pump だけで開始間隔ゲートも同時に満たす。
        var fakeNow = DateTime(2025, 1, 1);
        final lines = List.generate(500, (i) => 'line$i').join('\n');
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          settings: hyperlinksOnSettings,
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotWithLayoutFixture,
            'herdr pane read': '$lines\n',
          },
          herdrScrollbackLinkHelperRunner: runner,
          herdrCacheClock: () => fakeNow,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        await tester.pump(const Duration(milliseconds: 500));
        final callsAfterEntry = runner.calls;

        final dynamic state = tester.state(find.byType(TerminalScreen));
        // 実スクロール位置を中間の行へ移し、1回目とは異なる（未取得の）
        // 窓を要求させる。
        state.jumpToLineFromTopForTesting(250);
        await tester.pump();

        // 設定メニュー →「Disconnect」→ 確認ダイアログを開くところまでを
        // 先に済ませておく（メニュー・ダイアログの開閉アニメーションの
        // 時間経過を、停止待ち 400ms の計測が始まる前に消費させる）。
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();

        // ここから 400ms の停止待ちの計測を始める。
        final context = tester.element(find.byType(AnsiTextView));
        state.notifyViewportSettledForTesting(context);
        // 開始間隔 2 秒のゲートを、pump の実時間を消費せずに満たす
        // （後続の 420ms の pump だけで停止待ち 400ms の debounce タイマー
        // と両方を同時に満たすため）。
        fakeNow = fakeNow.add(const Duration(seconds: 3));

        // 確認ダイアログの「Close」を押す。disconnect()
        // （session_connection.dart）冒頭の env.onDisconnect?.call() は
        // 同期的に走る（その後の SSH 切断・Navigator.pop は非同期）。
        await tester.tap(find.text('Close'));
        await tester.pump();

        // このまま pumpAndSettle や大きめの
        // duration で進めると、Navigator.pop によるページ遷移アニメーションが
        // 完了して TerminalScreen 自体が dispose される
        // （disposeCaches() → scrollbackLinkReader.dispose() という、
        // onDisconnect の配線とは別経路でも保留が消える）ため、
        // 「往復が起きない」ことが配線ではなく dispose によるものと
        // 区別できなくなる。実測（プローブテストで確認）では、この時点から
        // 420ms の pump では画面はまだ dispose されておらず、500ms の pump
        // では dispose される。420ms は 400ms の停止待ちを超えるため、
        // 画面が生きている（dispose 経由ではない）うちに、cancelPending
        // 配線の有無だけで結果が分かれる形で検証できる。
        await tester.pump(const Duration(milliseconds: 420));

        expect(
          find.byType(TerminalScreen).evaluate().isNotEmpty,
          isTrue,
          reason:
              'この時点ではまだ TerminalScreen が dispose されていないこと'
              '（dispose 経由の disposeCaches ではなく、onDisconnect の配線を'
              '検証するための前提）',
        );

        expect(
          runner.calls,
          callsAfterEntry,
          reason:
              '切断操作直前に予約した保留中の取得が cancelPending で'
              '抑止され、開始間隔 2 秒・停止待ち 400ms を超えても、未取得の'
              '窓への追加の往復が発生しないこと（onDisconnect の配線）',
        );
      });
    });
  });
}
