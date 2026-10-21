import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart'
    show PaneHyperlink, PaneHyperlinkRange, PaneHyperlinks;
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_layout_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';
import 'helpers/scroll_send_test_helpers.dart' show enterMode, mode;
import 'helpers/herdr_experimental_settings.dart';

/// テスト用: 通常表示のハイパーリンク reader（herdr OSC 8 ハイパーリンク
/// 実験機能）。caret 用の fake reader と同型。
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

void main() {
  group('TerminalScreen herdr caret (Phase 4)', () {
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
  });
}
