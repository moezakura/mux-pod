/// `HerdrScrollbackLinkReader` のテストで共有する fixture。
///
/// `HerdrScrollbackLinkReader` の既定 `clock`（`DateTime.now`）は生の壁時計
/// で、FakeAsync は素の `DateTime.now()` を仮想化しない。そのため開始間隔の
/// 判定を検証するテストでは、`clock:` に手動で進める [now] を注入する。
/// [advance] は [now] と仮想タイマーの両方を同じ量だけ進める。
///
/// 各テストファイルは `setUp(setUpScrollbackLinkReaderFixture)` で状態を
/// 初期化する。
library;

import 'dart:async';

import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// [HerdrScrollbackLinkHelperRunner] の fake。
class FakeScrollbackLinkRunner implements HerdrScrollbackLinkHelperRunner {
  int calls = 0;
  final List<List<int>> offsetsPerCall = [];

  /// 呼び出しごとに返す結果を差し替えられる（デフォルトは空の窓）。
  ScrollbackLinksResult Function(List<int> offsets)? onRun;

  /// 設定時は [run] がこの完了まで待機する（in-flight 状態を作る）。
  Completer<void>? gate;

  @override
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  }) async {
    calls++;
    offsetsPerCall.add(offsetsFromBottom);
    final g = gate;
    if (g != null) await g.future;
    final handler = onRun;
    if (handler != null) return handler(offsetsFromBottom);
    return ScrollbackLinksResult(
      windows: [
        for (final offset in offsetsFromBottom)
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
  }
}

const _status = HerdrStatus(serverProtocol: 22, socket: '/tmp/herdr.sock');

late FakeScrollbackLinkRunner runner;
late ScrollbackLinkCache cache;
late List<void Function()> updates;
late bool active;
late String? paneId;
late int cols;
late int rows;
late int? viewportRows;
late Object? identity;
late int liveGeneration;
late List<String> bodyLines;
late DateTime now;

HerdrScrollbackLinkReader makeReader({
  Duration stopDebounce = const Duration(milliseconds: 400),
  Duration minInterval = const Duration(seconds: 2),
  Duration busyRetryDelay = const Duration(seconds: 2),
}) {
  return HerdrScrollbackLinkReader(
    runner: runner,
    cache: cache,
    status: () => _status,
    currentPane: () => paneId == null
        ? null
        : (paneId: paneId!, cols: cols, rows: rows, viewportRows: viewportRows),
    bodyLinesFor: () => bodyLines,
    onUpdated: () {
      for (final fn in updates) {
        fn();
      }
    },
    isActive: () => active,
    // await 後の identity/generation 再照合用。`identity`/`liveGeneration` は
    // テストが往復中に書き換えて再接続を模擬する（`paneId` を使った
    // 既存の pane 切替テストと同じ手法）。
    currentSnapshotIdentity: () => liveGeneration == 0
        ? null
        : (identity: identity, generation: liveGeneration),
    stopDebounce: stopDebounce,
    minInterval: minInterval,
    busyRetryDelay: busyRetryDelay,
    clock: () => now,
  );
}

/// 各テストの前に呼び、共有する状態を既定値へ戻す。
void setUpScrollbackLinkReaderFixture() {
  runner = FakeScrollbackLinkRunner();
  cache = ScrollbackLinkCache();
  updates = [];
  active = true;
  paneId = 'w1:t1:p1';
  cols = 80;
  // pane の viewport 行数（R）。既存テストの多くは
  // 表示範囲の行数と同じ 20 を既定にして、単一窓（表示範囲が R を
  // 超えない）のケースを基本形にする。
  rows = 20;
  // viewportRows は既定 null（未設定時の既存挙動の回帰確認用）。個別テストで上書きする。
  viewportRows = null;
  identity = Object();
  liveGeneration = 1;
  bodyLines = List.generate(200, (i) => 'line $i');
  now = DateTime(2024, 1, 1);
}

({Object? identity, int generation}) snap(int generation) =>
    (identity: identity, generation: generation);

/// `now`（reader へ注入した clock）と FakeAsync の仮想タイマーを同じ量
/// だけ進める。
Future<void> advance(WidgetTester tester, Duration d) async {
  now = now.add(d);
  await tester.pump(d);
}
