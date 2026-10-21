/// herdr_scrollback_link_reader.dart のテスト（窓の計算とキャッシュ反映）。
///
/// 表示範囲から要求する窓の個数と位置、frame 行数の引き継ぎ、取得済み範囲の
/// 扱い、整列結果のキャッシュ反映を確認する。共有する状態と補助関数は
/// `helpers/scrollback_link_reader_fixture.dart` にある。
library;

import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_alignment.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/scrollback_link_reader_fixture.dart';

void main() {
  setUp(setUpScrollbackLinkReaderFixture);

  testWidgets('取得済みの範囲は再取得しない', (tester) async {
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);
    // R=20（pane.rows）、表示範囲の行数も20（180..199）で R を超えない
    // ため単一窓。a = 200-1-199 = 0。
    expect(runner.offsetsPerCall.single, [0]);

    // 同じ範囲で再度止まる（2秒経過後）。
    await advance(tester, const Duration(seconds: 2));
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // offset 0 は取得済みなので窓が無く、往復しない。
    expect(runner.calls, 1);
  });

  testWidgets('truncated の窓（拒否された窓・出力量で入りきらなかった窓）は取得済みにせず、次に止まったとき再取得する', (
    tester,
  ) async {
    runner.onRun = (offsets) => ScrollbackLinksResult(
      windows: [
        for (final offset in offsets)
          ScrollbackLinkWindow(
            requestedOffset: offset,
            actualOffset: offset,
            hyperlinks: const PaneHyperlinks(
              frameWidth: 80,
              frameHeight: 20,
              links: [],
              rowFingerprints: {},
              truncated: true,
            ),
          ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);
    expect(cache.hasFetched(0), isFalse);

    // 同じ範囲で再度止まる（2秒経過後）: truncated の窓は再取得される。
    await advance(tester, const Duration(seconds: 2));
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 2);
    expect(runner.offsetsPerCall.last, [0]);

    // 新しい停止が無ければ、時間が経っても再取得しない。
    await advance(tester, const Duration(seconds: 10));
    await tester.pump();
    expect(runner.calls, 2);
  });

  testWidgets('表示範囲が R 行を超えないときは単一窓', (tester) async {
    final reader = makeReader();
    // R=20（既定）、top=0..19（表示範囲20行）は R を超えないため単一窓。
    // a = 200-1-19 = 180。
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.offsetsPerCall.single, [180]);
  });

  testWidgets('表示範囲が R 超 2R 以下のときは2窓', (tester) async {
    // R=10（pane の viewport 行数）。表示範囲15行（top=185..199）は
    // R(10) を超え 2R(20) 以下のため、a, a+R の2窓のみ（3窓目 a+2R は
    // 要求しない）。
    rows = 10;
    final reader = makeReader();
    reader.onViewportSettled(snap(1), 200, (top: 185, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // a = 200-1-199 = 0, a+R = 10。
    expect(runner.offsetsPerCall.single, [0, 10]);
  });

  testWidgets('複数窓: 表示範囲が 2R を超えるときは a, a+R, a+2R を要求する（上限3個）', (tester) async {
    // R=10（pane の viewport 行数）。表示範囲100行（top=100..199）は
    // 2R(20) を超えるため、a, a+R, a+2R の3窓を要求する
    // （1回で取る窓は最大3＝viewport の行数×3行まで）。
    rows = 10;
    final reader = makeReader();
    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // a = 1000-1-199 = 800, a+R=810, a+2R=820（いずれも lineCount 未満）。
    expect(runner.offsetsPerCall.single, [800, 810, 820]);
  });

  testWidgets('表示範囲が 3R を超えても3窓のまま増えない（上限3）', (tester) async {
    // R=10。表示範囲35行（3R=30を超える）でも、窓は a, a+R, a+2R の
    // 3個のまま（4個目 a+3R は要求しない）。
    rows = 10;
    final reader = makeReader();
    reader.onViewportSettled(snap(1), 1000, (top: 165, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    // a = 1000-1-199 = 800, a+R=810, a+2R=820。
    expect(runner.offsetsPerCall.single, [800, 810, 820]);
  });

  testWidgets('窓タイリングの R は、直近の helper 実測 frame 行数'
      '（ScrollbackLinkCache.lastFrameRows）があればそれを最優先する'
      '（pane.rows=20 のままでも無視されること）', (tester) async {
    // helper が実際に使った行数（7）を直接キャッシュへ設定する
    // （直近の往復で判明した値、という想定）。
    cache.resetIfNeeded(identity: identity, generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 999,
      linksByBodyLine: const {},
      frameRows: 7,
    );
    final reader = makeReader();

    // pane.rows は既定の20のまま（_resolveWindowRowSpan が lastFrameRows
    // を優先するなら無視されるはず）。表示範囲100行は R=7 なら上限3窓
    // （ceil(100/7)=15 を3で頭打ち）、間隔は7。
    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // a = 1000-1-199 = 800。間隔7で a, a+7, a+14。
    expect(runner.offsetsPerCall.single, [800, 807, 814]);
  });

  testWidgets('窓タイリングの R は、lastFrameRows が無く viewportRows があればそれを'
      '使う（pane.rows=20 のままでも無視される'
      'こと）', (tester) async {
    viewportRows = 5;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // a = 1000-1-199 = 800。間隔5で a, a+5, a+10。
    expect(runner.offsetsPerCall.single, [800, 805, 810]);
  });

  testWidgets('viewportRows が 0 以下でも素通しされるが、最終的に pane.rows へ'
      'フォールバックする（viewportRows を作る parser 側では正規化せず、0 もそのまま渡ってくる前提）', (
    tester,
  ) async {
    viewportRows = 0;
    rows = 10;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // viewportRows=0 は無効として読み飛ばし、pane.rows=10 を使う。
    expect(runner.offsetsPerCall.single, [800, 810, 820]);
  });

  testWidgets('helper が実際に使った frame 行数が requested rows と異なっても、次回の'
      '窓タイリングにギャップが出ない（helper が実 '
      'pty サイズを優先し、Dart が要求した rows=20 とは違う7行で返してきた'
      '場合、次の往復はその7行基準で隙間なく並ぶ）', (tester) async {
    bodyLines = ['alpha', 'bravo', 'charlie', 'delta', 'echo'];
    // helper は要求（rows=20）とは無関係に、実際に使った行数7を返す。
    runner.onRun = (offsets) => ScrollbackLinksResult(
      windows: [
        for (final offset in offsets)
          ScrollbackLinkWindow(
            requestedOffset: offset,
            actualOffset: offset,
            hyperlinks: const PaneHyperlinks(
              frameWidth: 80,
              frameHeight: 7, // 要求 rows=20 とは異なる実測値
              links: [],
              rowFingerprints: {},
              truncated: false,
            ),
          ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
    final reader = makeReader();

    // 1回目: 単一窓（表示範囲20行は pane.rows=20 を超えない）。
    reader.onViewportSettled(snap(1), 1000, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.offsetsPerCall.single, [800]);
    expect(cache.lastFrameRows, 7);

    // 2回目: 1回目の実測（frameRows=7）が次の窓計算に反映され、間隔7で
    // 隙間なく並ぶ（pane.rows=20 を使った場合の間隔20にはならない）。
    // 窓の計算自体は [800, 807, 814] だが、800 は1回目で取得済みのため
    // 「取得済みの範囲は再取得しない」ため除外され、実際に要求
    // するのは [807, 814] になる（間隔7は変わらない＝ギャップなし）。
    reader.onViewportSettled(snap(1), 1000, (top: 100, bottom: 199));
    await advance(tester, const Duration(seconds: 2));
    await tester.pump();
    expect(runner.offsetsPerCall.last, [807, 814]);
  });

  testWidgets('直近に採用した k（lastK）が次回の窓計算に引き継がれる（k_est）', (tester) async {
    // 前回のスナップショットで採用済みの k=3 を直接キャッシュへ設定する
    // （k_est は同じスナップショットで最後に採用した k）。
    cache.resetIfNeeded(identity: identity, generation: 1);
    cache.applyWindowResult(
      generation: 1,
      offsetFromBottom: 999,
      linksByBodyLine: const {},
      k: 3,
    );
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    // a = (200-1-199) + k_est(3) = 3（表示範囲20行は R=20 を超えないため
    // 単一窓）。offset 999 は既に取得済みだが、offset 3 は未取得のため
    // 往復する。
    expect(runner.offsetsPerCall.single, [3]);
  });

  testWidgets('整列に成功した窓の結果がキャッシュへ反映される', (tester) async {
    bodyLines = ['alpha', 'bravo', 'charlie', 'delta', 'echo'];
    runner.onRun = (offsets) => ScrollbackLinksResult(
      windows: [
        ScrollbackLinkWindow(
          requestedOffset: offsets.single,
          actualOffset: offsets.single,
          hyperlinks: PaneHyperlinks(
            frameWidth: 80,
            frameHeight: 5,
            links: const [
              PaneHyperlink(
                url: 'https://example.test',
                ranges: [PaneHyperlinkRange(row: 2, startCol: 0, endCol: 6)],
              ),
            ],
            rowFingerprints: {
              for (var i = 0; i < 5; i++)
                i: HerdrRowFingerprint.rowFingerprint(bodyLines[i])!,
            },
            truncated: false,
          ),
        ),
      ],
      restore: ScrollbackLinkRestore.exact,
    );
    var updateCount = 0;
    updates.add(() => updateCount++);
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 5, (top: 0, bottom: 4));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();

    expect(updateCount, 1);
    expect(cache.generation, 1);
    // frameRow=2, windowOffset=0, frameRows=5, bodyLineCount=5, k=0 →
    // d = 0+(5-1-2)=2, i=(5-1-2)+0=2 → charlie 行。
    expect(cache.linksByBodyLine[2], isNotNull);
    expect(cache.linksByBodyLine[2]!.single.url, 'https://example.test');
  });
}
