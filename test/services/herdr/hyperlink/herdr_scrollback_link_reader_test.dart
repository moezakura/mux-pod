/// herdr_scrollback_link_reader.dart のテスト。
///
/// [HerdrScrollbackLinkReader] は `Timer` による停止待ち 400ms・開始間隔
/// 2秒・busy 再試行 2秒を内部で使うため、`flutter_test` の
/// `TestWidgetsFlutterBinding` が test 本体全体を包む FakeAsync ゾーンを
/// 利用する（`testWidgets` を widget を pump せずに使い、
/// `tester.pump(duration)` でタイマーを進める）。
///
/// `HerdrScrollbackLinkReader` の既定 `clock`（`DateTime.now`）は生の壁時計
/// で、FakeAsync は `Timer` は仮想化するが素の `DateTime.now()` は仮想化
/// しない（`package:clock` の `clock.now()` 経由の呼び出しだけを差し替える）。
/// そのため開始間隔 2 秒の判定を検証するテストでは、`clock:` に手動で進める
/// `now` を注入する（`herdr_caret_snapshot_reader_test.dart` と同じ手法）。
/// [advance] は `now` と仮想タイマーの両方を同じ量だけ
/// 進める。
library;

import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_types.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/scrollback_link_reader_fixture.dart';

void main() {
  setUp(setUpScrollbackLinkReaderFixture);

  testWidgets('止めて400ms後に1回だけ往復する', (tester) async {
    final reader = makeReader();
    var updateCount = 0;
    updates.add(() => updateCount++);

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    expect(runner.calls, 0);

    await advance(tester, const Duration(milliseconds: 399));
    expect(runner.calls, 0);

    await advance(tester, const Duration(milliseconds: 1));
    await tester.pump();
    expect(runner.calls, 1);
    expect(updateCount, 1);
  });

  testWidgets('400ms以内の連続呼び出しは1回にまとまり最新の範囲を使う', (tester) async {
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 200));
    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 399));
    expect(runner.calls, 0);

    await advance(tester, const Duration(milliseconds: 1));
    await tester.pump();
    expect(runner.calls, 1);
    // bottom=199 → offset = 200-1-199 = 0（最新の範囲）。
    expect(runner.offsetsPerCall.single, contains(0));
  });

  testWidgets('前回の開始から2秒以内の停止はまとめて1回・最新の範囲を使う（trailing-edge）', (tester) async {
    final reader = makeReader();
    var updateCount = 0;
    updates.add(() => updateCount++);

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 1秒後（開始から2秒未満）に別範囲で止まる。
    await advance(tester, const Duration(milliseconds: 600));
    reader.onViewportSettled(snap(1), 200, (top: 0, bottom: 19));
    await advance(tester, const Duration(milliseconds: 400));
    // まだ開始から2秒経っていないので往復しない。
    expect(runner.calls, 1);

    // 開始から2秒経過。
    await advance(tester, const Duration(seconds: 1));
    await tester.pump();
    expect(runner.calls, 2);
    // top=0,bottom=19 → offset = 200-1-19 = 180。
    expect(runner.offsetsPerCall.last, contains(180));
    expect(updateCount, 2);
  });

  testWidgets('busy は2秒後に1回だけ再試行する', (tester) async {
    var callCount = 0;
    runner.onRun = (offsets) {
      callCount++;
      if (callCount == 1) {
        throw const HerdrCaretHelperException(
          HerdrCaretHelperFailure.execFailed,
          'busy',
          null,
          HerdrHelperErrorKind.busy,
        );
      }
      return ScrollbackLinksResult(
        windows: [
          for (final offset in offsets)
            ScrollbackLinkWindow(
              requestedOffset: offset,
              actualOffset: offset,
              hyperlinks: const PaneHyperlinks(
                frameWidth: 80,
                frameHeight: 0,
                links: [],
                rowFingerprints: {},
                truncated: false,
              ),
            ),
        ],
        restore: ScrollbackLinkRestore.exact,
      );
    };
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 400));
    await tester.pump();
    expect(runner.calls, 1);

    // 2秒未満では再試行しない。
    await advance(tester, const Duration(milliseconds: 1999));
    expect(runner.calls, 1);

    await advance(tester, const Duration(milliseconds: 1));
    await tester.pump();
    expect(runner.calls, 2);

    // 再試行後さらに時間が経っても3回目は起きない（1回だけ）。
    await advance(tester, const Duration(seconds: 5));
    expect(runner.calls, 2);
  });

  testWidgets('バックグラウンド中は往復0回', (tester) async {
    active = false;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 0);
  });

  testWidgets('captureTargetIdentity() が null なら往復しない', (tester) async {
    identity = null;
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 0);
  });

  testWidgets('cancelPending は待機中の取得を捨てる', (tester) async {
    final reader = makeReader();

    reader.onViewportSettled(snap(1), 200, (top: 180, bottom: 199));
    await advance(tester, const Duration(milliseconds: 100));
    reader.cancelPending();
    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(runner.calls, 0);
  });
}
