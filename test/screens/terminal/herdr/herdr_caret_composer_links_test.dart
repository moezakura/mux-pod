/// HerdrCaretComposer のリンク系メソッド（通常ハイパーリンクとスクロール
/// モードのリンクの準備、現在 pane の解決、viewport 確定の保持）のテスト。
///
/// 手書き fake（[FakeHerdrCaretHost]）で `HerdrCaretHost` を実装する。fake と
/// 補助関数は `helpers/herdr_caret_composer_fakes.dart` に置いている。
library;

import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/herdr/herdr_caret.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_snapshot_cache.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart'
    show PaneHyperlinks;
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart'
    show
        HerdrScrollbackLinkHelperRunner,
        ScrollbackLinkRestore,
        ScrollbackLinksResult,
        ScrollbackLinkWindow;
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_ssh_client.dart';

import '../helpers/herdr_caret_composer_fakes.dart';

void main() {
  group('HerdrCaretComposer.setupHyperlinkProduction', () {
    testWidgets('設定 OFF では hyperlinkReader を構築しない', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(
          tester,
          ssh,
          settings: const AppSettings(
            keepScreenOn: false,
            experimentalHerdrHyperlinksEnabled: false,
          ),
        ),
      );
      final composer = HerdrCaretComposer(host);

      await composer.setupHyperlinkProduction(ssh);

      expect(host.hyperlinkReader, isNull);
      expect(host.setFrameReaderCalls, 0);
    });

    testWidgets('snapshotCache が無ければ何もしない', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(
          tester,
          ssh,
          settings: const AppSettings(
            keepScreenOn: false,
            experimentalHerdrHyperlinksEnabled: true,
          ),
        ),
      );
      final composer = HerdrCaretComposer(host);

      await composer.setupHyperlinkProduction(ssh);

      expect(host.hyperlinkReader, isNull);
      expect(host.setFrameReaderCalls, 0);
    });
  });

  group('HerdrCaretComposer.resolveInjectedScrollbackLinkRunner / '
      'setupScrollbackLinkReader', () {
    testWidgets('設定OFFでは注入 runner があってもnullを返す', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(
          tester,
          ssh,
          settings: const AppSettings(
            keepScreenOn: false,
            experimentalHerdrHyperlinksEnabled: false,
          ),
        ),
      );
      host.injectedScrollbackLinkHelperRunnerValue =
          _FakeScrollbackLinkRunner();
      final composer = HerdrCaretComposer(host);

      expect(composer.resolveInjectedScrollbackLinkRunner(), isNull);
    });

    testWidgets('設定ONかつ注入ありならそれを返す（本番SSH呼び出しなし）', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(
          tester,
          ssh,
          settings: const AppSettings(
            keepScreenOn: false,
            experimentalHerdrHyperlinksEnabled: true,
          ),
        ),
      );
      final runner = _FakeScrollbackLinkRunner();
      host.injectedScrollbackLinkHelperRunnerValue = runner;
      final composer = HerdrCaretComposer(host);

      expect(composer.resolveInjectedScrollbackLinkRunner(), same(runner));
    });

    testWidgets('setupScrollbackLinkReader は設定OFFでは何もしない', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(
          tester,
          ssh,
          settings: const AppSettings(
            keepScreenOn: false,
            experimentalHerdrHyperlinksEnabled: false,
          ),
        ),
      );
      host.scrollbackLinkCache = ScrollbackLinkCache();
      final composer = HerdrCaretComposer(host);

      await composer.setupScrollbackLinkReader(ssh);

      expect(host.scrollbackLinkReader, isNull);
    });

    testWidgets('setupScrollbackLinkReader はscrollbackLinkCacheが無ければ何もしない', (
      tester,
    ) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(
          tester,
          ssh,
          settings: const AppSettings(
            keepScreenOn: false,
            experimentalHerdrHyperlinksEnabled: true,
          ),
        ),
      );
      final composer = HerdrCaretComposer(host);

      await composer.setupScrollbackLinkReader(ssh);

      expect(host.scrollbackLinkReader, isNull);
    });

    testWidgets('setupScrollbackLinkReader は注入runnerがあれば何もしない（早期return）', (
      tester,
    ) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(
          tester,
          ssh,
          settings: const AppSettings(
            keepScreenOn: false,
            experimentalHerdrHyperlinksEnabled: true,
          ),
        ),
      );
      host.scrollbackLinkCache = ScrollbackLinkCache();
      host.injectedScrollbackLinkHelperRunnerValue =
          _FakeScrollbackLinkRunner();
      final composer = HerdrCaretComposer(host);

      await composer.setupScrollbackLinkReader(ssh);

      expect(host.scrollbackLinkReader, isNull);
    });
  });

  group('HerdrCaretComposer.currentScrollbackLinkPane', () {
    testWidgets('rect の width・height がともに 0 のときは null を返す'
        '（v0.7.5 で client が一度も attach していない間は rect/area が'
        '0x0 になる）', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      host.currentPaneIdValue = 'w1:p1';
      host.snapshotCacheValue = await _cacheWithPaneRect(
        paneId: 'w1:p1',
        rect: const HerdrRect(width: 0, height: 0),
      );
      final composer = HerdrCaretComposer(host);

      expect(composer.currentScrollbackLinkPane(), isNull);
    });

    testWidgets('rect が 0x0 でなければ paneId・cols・rows を返す（回帰確認）', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      host.currentPaneIdValue = 'w1:p1';
      host.snapshotCacheValue = await _cacheWithPaneRect(
        paneId: 'w1:p1',
        rect: const HerdrRect(width: 120, height: 40),
      );
      final composer = HerdrCaretComposer(host);

      final pane = composer.currentScrollbackLinkPane();
      expect(pane?.paneId, 'w1:p1');
      expect(pane?.cols, 120);
      expect(pane?.rows, 40);
    });

    testWidgets(
      'viewportRows は snapshot.paneFor(paneId)?.viewportRows から渡される',
      (tester) async {
        final ssh = FakeSshClient();
        final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
        host.currentPaneIdValue = 'w1:p1';
        host.snapshotCacheValue = await _cacheWithPaneRect(
          paneId: 'w1:p1',
          rect: const HerdrRect(width: 120, height: 40),
          viewportRows: 23,
        );
        final composer = HerdrCaretComposer(host);

        expect(composer.currentScrollbackLinkPane()?.viewportRows, 23);
      },
    );

    testWidgets('flat panes[] に paneId が無ければ viewportRows は null'
        '（snapshot.paneFor が null を返す経路）', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      host.currentPaneIdValue = 'w1:p1';
      host.snapshotCacheValue = await _cacheWithPaneRect(
        paneId: 'w1:p1',
        rect: const HerdrRect(width: 120, height: 40),
        includeFlatPane: false,
      );
      final composer = HerdrCaretComposer(host);

      expect(composer.currentScrollbackLinkPane()?.viewportRows, isNull);
    });
  });

  group('HerdrCaretComposer.notifyViewportSettled / '
      'onScrollbackLinkReaderAssigned', () {
    // 本番の setupScrollbackLinkReader は HerdrCaretHelperManifest.load()
    // （rootBundle 経由のアセット読込）を経由するが、この統合テスト環境
    // では到達できない（terminal_screen_herdr_caret_test.dart の
    // 「caret・hyperlinks とも ON でも status 取得は1回にまとまる」テスト内の
    // コメントと同じ制約）。そのため、reader 代入は setupScrollbackLinkReader を経由せず
    // buildScrollbackLinkReader の直接呼び出しで模し、
    // onScrollbackLinkReaderAssigned（本番では setupScrollbackLinkReader
    // の成功パス・HerdrLinkComposer.setupScrollbackLinkReader から呼ばれる）を直接呼んで
    // 「代入前に届いた settle が代入後に 1 回だけ再送される」核心部分を
    // 検証する。
    const identity = (identity: 'id-1', generation: 1);
    const lineCount = 2;
    const range = (top: 0, bottom: 1);

    Future<FakeHerdrCaretHost> buildReadyHost(WidgetTester tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      host.scrollbackLinkCache = ScrollbackLinkCache();
      host.currentPaneIdValue = 'w1:p1';
      host.bodyLinesForValue = const ['line0', 'line1'];
      host.currentSnapshotIdentityValue = identity;
      host.snapshotCacheValue = await _cacheWithPaneRect(
        paneId: 'w1:p1',
        rect: const HerdrRect(width: 120, height: 40),
      );
      return host;
    }

    testWidgets('reader 未代入中に届いた settle は、代入後に 1 回だけ再送される', (tester) async {
      final host = await buildReadyHost(tester);
      final composer = HerdrCaretComposer(host);
      final runner = _WorkingScrollbackLinkRunner();

      // reader 未代入（setupScrollbackLinkReader の manifest 読込
      // await 中に相当）のときに settle が届く。
      composer.notifyViewportSettled(identity, lineCount, range);
      expect(host.scrollbackLinkReader, isNull, reason: '未代入中は転送されないこと');

      // reader 代入が完了する（本番: setupScrollbackLinkReader の
      // 成功パス）。
      host.scrollbackLinkReader = composer.buildScrollbackLinkReader(runner);
      composer.onScrollbackLinkReaderAssigned();

      // 停止待ち 400ms を経て 1 回だけ往復すること。
      await tester.pump(const Duration(milliseconds: 500));
      expect(runner.calls, 1, reason: '代入前に届いた settle が代入後に 1 回だけ再送されること');
    });

    testWidgets('対照: onScrollbackLinkReaderAssigned を呼ばなければ、代入後も往復は'
        '発生しない（reader 未代入中は settle が捨てられていたことの確認）', (tester) async {
      final host = await buildReadyHost(tester);
      final composer = HerdrCaretComposer(host);
      final runner = _WorkingScrollbackLinkRunner();

      composer.notifyViewportSettled(identity, lineCount, range);
      host.scrollbackLinkReader = composer.buildScrollbackLinkReader(runner);
      // onScrollbackLinkReaderAssigned を呼ばない。

      await tester.pump(const Duration(milliseconds: 500));
      expect(runner.calls, 0, reason: '再送を呼ばなければ往復が発生しないこと（対照）');
    });

    testWidgets('select モードでなくなっていれば再送しない', (tester) async {
      final host = await buildReadyHost(tester);
      host.isSelectModeActiveValue = false;
      final composer = HerdrCaretComposer(host);
      final runner = _WorkingScrollbackLinkRunner();

      composer.notifyViewportSettled(identity, lineCount, range);
      host.scrollbackLinkReader = composer.buildScrollbackLinkReader(runner);
      composer.onScrollbackLinkReaderAssigned();

      await tester.pump(const Duration(milliseconds: 500));
      expect(runner.calls, 0, reason: 'select モードを抜けていれば再送しないこと');
    });
  });

  group('HerdrCaretComposer の準備中にスナップショットが差し替わった場合', () {
    const settings = AppSettings(
      keepScreenOn: false,
      experimentalHerdrHyperlinksEnabled: true,
    );

    // setup 系が snapshotCache を読む順序は、1 回目が開始時の取得、
    // 2 回目が manifest 読込後の確認、3 回目が installer 取得後の確認。
    Future<FakeHerdrCaretHost> pumpHost(
      WidgetTester tester,
      FakeSshClient ssh, {
      int? swapOnRead,
    }) async {
      final host = FakeHerdrCaretHost(
        ref: await pumpRefFor(tester, ssh, settings: settings),
      );
      host.snapshotCacheValue = HerdrSnapshotCache(() => HerdrAdapter(ssh));
      host.frameAdapterValue = HerdrAdapter(ssh);
      host.scrollbackLinkCache = ScrollbackLinkCache();
      if (swapOnRead != null) {
        host.swapSnapshotCacheTo = HerdrSnapshotCache(() => HerdrAdapter(ssh));
        host.swapSnapshotCacheOnRead = swapOnRead;
      }
      return host;
    }

    testWidgets('setupHyperlinkProduction は manifest 読込中に差し替わると'
        ' hyperlinkReader を登録しない', (tester) async {
      final ssh = FakeSshClient();

      final control = await pumpHost(tester, ssh);
      await tester.runAsync(
        () => HerdrCaretComposer(control).setupHyperlinkProduction(ssh),
      );
      expect(control.hyperlinkReader, isNotNull, reason: '差し替えなしなら登録される');
      expect(control.setFrameReaderCalls, 1);

      final host = await pumpHost(tester, ssh, swapOnRead: 2);
      await tester.runAsync(
        () => HerdrCaretComposer(host).setupHyperlinkProduction(ssh),
      );
      expect(host.hyperlinkReader, isNull);
      expect(host.setFrameReaderCalls, 0);
    });

    testWidgets('setupHyperlinkProduction は installer 取得の待機中に差し替わると'
        ' hyperlinkReader を登録しない', (tester) async {
      final ssh = FakeSshClient();

      final host = await pumpHost(tester, ssh, swapOnRead: 3);
      await tester.runAsync(
        () => HerdrCaretComposer(host).setupHyperlinkProduction(ssh),
      );
      expect(host.hyperlinkReader, isNull);
      expect(host.setFrameReaderCalls, 0);
    });

    testWidgets('setupScrollbackLinkReader は manifest 読込中・installer 取得の'
        '待機中のどちらで差し替わっても reader を登録しない', (tester) async {
      final ssh = FakeSshClient();

      final control = await pumpHost(tester, ssh);
      await tester.runAsync(
        () => HerdrCaretComposer(control).setupScrollbackLinkReader(ssh),
      );
      expect(control.scrollbackLinkReader, isNotNull, reason: '差し替えなしなら登録される');

      for (final swapOnRead in [2, 3]) {
        final host = await pumpHost(tester, ssh, swapOnRead: swapOnRead);
        await tester.runAsync(
          () => HerdrCaretComposer(host).setupScrollbackLinkReader(ssh),
        );
        expect(
          host.scrollbackLinkReader,
          isNull,
          reason: '$swapOnRead 回目の読み出しで差し替わった場合',
        );
      }
    });
  });
}

/// [paneId] に固定の [rect] を持つ 1 layout の snapshot を [HerdrSnapshotCache]
/// に投入して返す（[HerdrCaretComposer.currentScrollbackLinkPane]
/// テスト用。`HerdrCaretHelperManifest.load()` を経由しない検証方針は
/// 既存の [testManifest] と同じ）。
Future<HerdrSnapshotCache> _cacheWithPaneRect({
  required String paneId,
  required HerdrRect rect,
  // snapshot.paneFor(paneId) -> viewportRows の結線を
  // テストできるよう、flat な panes[]（HerdrPane）も用意する。
  // null のままなら `HerdrPane.viewportRows` は未設定（null）。
  int? viewportRows,
  // flat panes[] に当該 paneId を含めるかどうか（含めない場合
  // `snapshot.paneFor(paneId)` は null になり、viewportRows も null になる
  // ことを確認するためのテスト用スイッチ）。
  bool includeFlatPane = true,
}) async {
  final adapter = _FakeSnapshotAdapter()
    ..snapshotValue = HerdrSnapshot(
      panes: includeFlatPane
          ? [
              HerdrPane(
                id: paneId,
                workspaceId: 'w1',
                tabId: 'w1:t1',
                viewportRows: viewportRows,
              ),
            ]
          : const [],
      layouts: [
        HerdrLayout(
          panes: [HerdrLayoutPane(paneId: paneId, rect: rect)],
        ),
      ],
    );
  final cache = HerdrSnapshotCache(() => adapter);
  await cache.get();
  return cache;
}

/// [HerdrAdapter.snapshot] を固定値で差し替える fake（currentScrollbackLinkPane テスト用）。
class _FakeSnapshotAdapter extends HerdrAdapter {
  _FakeSnapshotAdapter() : super(FakeSshClient());

  HerdrSnapshot snapshotValue = const HerdrSnapshot();

  @override
  Future<HerdrSnapshot> snapshot({Duration? timeout}) async => snapshotValue;
}

/// 実際に成功する scrollback-links runner の fake（notifyViewportSettled / onScrollbackLinkReaderAssigned のテスト用。
/// [_FakeScrollbackLinkRunner] は早期return確認専用で常に throw するため
/// 使えない）。
class _WorkingScrollbackLinkRunner implements HerdrScrollbackLinkHelperRunner {
  int calls = 0;

  @override
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  }) async {
    calls++;
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

class _FakeScrollbackLinkRunner implements HerdrScrollbackLinkHelperRunner {
  int calls = 0;

  @override
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  }) {
    calls++;
    throw UnimplementedError('このテストでは呼ばれない想定');
  }
}
