/// HerdrCaretComposer.ensureStatus() のテスト（herdr OSC 8
/// ハイパーリンク実験機能・Herdr status の single-flight 共有）。
///
/// 手書き fake（[_FakeHerdrCaretHost]）で [HerdrCaretHost] を実装し、
/// SSH 実行は [FakeSshClient] で観測する。`refreshStatus` は取得中の再接続で
/// 古い client の status を書き戻さないことを確認するため
/// `_host.ref.read(sshProvider.notifier).client` を参照する。
/// そのため `ref` は本物の [WidgetRef] を、最小限の widget を pump して得る
/// （`testWidgets` を使う。他のフィールドは手書き fake のまま）。
library;

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/herdr/herdr_caret.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manifest.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_snapshot_cache.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart'
    show PaneHyperlinks;
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_helper_manager.dart'
    show
        HerdrScrollbackLinkHelperRunner,
        ScrollbackLinkRestore,
        ScrollbackLinksResult,
        ScrollbackLinkWindow;
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_scrollback_link_reader.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/scrollback_link_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_settings_notifier.dart';
import '../../../helpers/fake_ssh_client.dart';
import '../../../helpers/fake_ssh_notifier.dart';

/// [HerdrCaretHelperManager]/[HerdrHyperlinkHelperManager] の配置確認と
/// 同型の最小 manifest（`.load()`（アセットバンドル読込）を経由せずに
/// [HerdrCaretComposer.ensureInstaller] を直接検証するため）。
HerdrCaretHelperManifest _testManifest() => HerdrCaretHelperManifest.fromJson(
  jsonEncode({
    'version': 1,
    'helperName': 'herdr-caret-helper',
    'platforms': [
      {
        'id': 'linux-x86_64',
        'os': 'linux',
        'arch': 'x86_64',
        'asset': 'assets/herdr-caret-helper/linux-x86_64/herdr-caret-helper',
        'size': 1,
        'sha256': ''.padLeft(64, '0'),
      },
    ],
  }),
);

// 実測: server 稼働時の `herdr status --json`（herdr_adapter_status_test.dart
// の kStatusOk と同一値）。
const _kStatusOk =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,"compatible":true,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

class _FakeHerdrCaretHost implements HerdrCaretHost {
  _FakeHerdrCaretHost({required this.ref});

  bool isDisposedValue = false;

  HerdrStatus? caretStatusValue;

  /// null 固定ではなくテストから差し込めるようにする（
  /// setupHyperlinkProduction / setupProduction は snapshotCache /
  /// frameAdapter が非 null であることを要求する）。
  HerdrSnapshotCache? snapshotCacheValue;
  HerdrAdapter? frameAdapterValue;

  int setFrameReaderCalls = 0;

  @override
  final WidgetRef ref;

  @override
  bool get isMounted => true;

  @override
  bool get isDisposed => isDisposedValue;

  @override
  MultiplexerBackendKind get backendKind => MultiplexerBackendKind.herdr;

  @override
  HerdrAdapter? get frameAdapter => frameAdapterValue;

  @override
  HerdrSnapshotCache? get snapshotCache => snapshotCacheValue;

  @override
  HerdrCaretSnapshotReader? get injectedReader => null;

  @override
  HerdrHyperlinkReader? get injectedHyperlinkReader => null;

  @override
  HerdrCaretSnapshotReader? caretReader;

  @override
  HerdrStatus? get caretStatus => caretStatusValue;

  @override
  set caretStatus(HerdrStatus? value) => caretStatusValue = value;

  @override
  HerdrHyperlinkReader? hyperlinkReader;

  @override
  void setFrameReader(HerdrPaneFrameReader reader) => setFrameReaderCalls++;

  @override
  void clearViewCaret() {}

  // ---- スクロールモードのリンク読取用 ----
  String? currentPaneIdValue;

  @override
  String? get currentPaneId => currentPaneIdValue;

  @override
  ScrollbackLinkCache? scrollbackLinkCache;

  @override
  HerdrScrollbackLinkReader? scrollbackLinkReader;

  HerdrScrollbackLinkHelperRunner? injectedScrollbackLinkHelperRunnerValue;

  @override
  HerdrScrollbackLinkHelperRunner? get injectedScrollbackLinkHelperRunner =>
      injectedScrollbackLinkHelperRunnerValue;

  List<String> bodyLinesForValue = const [];

  @override
  List<String> Function() get bodyLinesFor =>
      () => bodyLinesForValue;

  bool isActiveValue = true;

  @override
  bool Function() get isActive =>
      () => isActiveValue;

  bool isSelectModeActiveValue = true;

  @override
  bool Function() get isSelectModeActive =>
      () => isSelectModeActiveValue;

  int notifyScrollbackLinksUpdatedCalls = 0;

  @override
  void Function() get notifyScrollbackLinksUpdated =>
      () => notifyScrollbackLinksUpdatedCalls++;

  ({Object? identity, int generation})? currentSnapshotIdentityValue;

  @override
  ({Object? identity, int generation})? Function()
  get currentSnapshotIdentity =>
      () => currentSnapshotIdentityValue;

  @override
  DateTime Function()? scrollbackLinkClock;
}

/// [sshProvider] を [client] で上書きした最小の widget を pump し、その
/// widget から得た本物の [WidgetRef] を返す（[_FakeHerdrCaretHost.ref] 用）。
///
/// [settings] が非 null なら [settingsProvider] も上書きする（
/// `experimentalHerdrHyperlinksEnabled` の判定に使う）。
Future<WidgetRef> _pumpRefFor(
  WidgetTester tester,
  FakeSshClient client, {
  AppSettings? settings,
}) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: client)),
        if (settings != null)
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(settings: settings),
          ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('HerdrCaretComposer.ensureStatus', () {
    testWidgets('既に caretStatus が取得済みなら即時返却する（SSH 実行なし）', (tester) async {
      final ssh = FakeSshClient();
      ssh.execOutputs['herdr status --json'] = _kStatusOk;
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
      host.caretStatusValue = const HerdrStatus(serverProtocol: 17);
      final composer = HerdrCaretComposer(host);

      final status = await composer.ensureStatus(ssh);

      expect(status.serverProtocol, 17);
      expect(
        ssh.execCommands.any((c) => c.contains('herdr status')),
        isFalse,
        reason: '既取得済みなら status 取得の SSH は 0 回であること',
      );
    });

    testWidgets('未取得なら1回だけ SSH で取得し、host.caretStatus へ反映する', (tester) async {
      final ssh = FakeSshClient();
      ssh.execOutputs['herdr status --json'] = _kStatusOk;
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      final status = await composer.ensureStatus(ssh);

      expect(status.serverProtocol, 17);
      expect(host.caretStatusValue?.serverProtocol, 17);
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        1,
      );
    });

    testWidgets('同時に呼ばれた ensureStatus は single-flight で1回に合流する', (
      tester,
    ) async {
      final ssh = FakeSshClient();
      ssh.execOutputs['herdr status --json'] = _kStatusOk;
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      final futures = [
        composer.ensureStatus(ssh),
        composer.ensureStatus(ssh),
        composer.ensureStatus(ssh),
      ];
      final results = await Future.wait(futures);

      for (final status in results) {
        expect(status.serverProtocol, 17);
      }
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        1,
        reason: '同時呼び出しは single-flight で1回の SSH 実行に合流すること',
      );
    });

    testWidgets('取得失敗時は既定値（const HerdrStatus()）を返す（throw しない）', (tester) async {
      final ssh = FakeSshClient();
      ssh.execExceptions['herdr status --json'] = Exception('boom');
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      final status = await composer.ensureStatus(ssh);

      expect(status, const HerdrStatus());
      expect(host.caretStatusValue, isNull);
    });

    testWidgets('取得完了後は in-flight フィールドが自己クリアされ、次回はまた1回実行する', (tester) async {
      final ssh = FakeSshClient();
      ssh.execExceptions['herdr status --json'] = Exception('boom');
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      // 1回目: 失敗して既定値。host.caretStatus は未設定のまま。
      await composer.ensureStatus(ssh);
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        1,
      );

      // in-flight が自己クリアされているため、2回目も新たに SSH を実行する
      // （直前の future に合流して 0 回になってはいけない）。
      await composer.ensureStatus(ssh);
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        2,
      );
    });

    testWidgets('再接続で client が差し替わった後に完了した取得は、古い client の status を'
        '書き戻さない', (tester) async {
      final oldClient = FakeSshClient();
      oldClient.execOutputs['herdr status --json'] = _kStatusOk;
      final ref = await _pumpRefFor(tester, oldClient);
      final host = _FakeHerdrCaretHost(ref: ref);
      final composer = HerdrCaretComposer(host);

      // refreshStatus が oldClient で fetch している間に、"現在の" client が
      // 別の client へ差し替わったのと同じ状態を作る（sshProvider.notifier の
      // client を直接書き換える。fetch 自体は oldClient 引数で行われる）。
      final notifier = ref.read(sshProvider.notifier) as FakeSshNotifier;
      final newClient = FakeSshClient();
      notifier.client = newClient;

      // oldClient を引数に渡して fetch する（内部で fetch 完了後に
      // 「現在の client」= newClient と照合し、不一致なら書き戻さない）。
      await composer.ensureStatus(oldClient);

      expect(
        host.caretStatusValue,
        isNull,
        reason: '取得完了時に現在の client と不一致なら caretStatus を書き戻さないこと',
      );
    });
  });

  group('HerdrCaretComposer.ensureInstaller（helper installer '
      'の共有）', () {
    testWidgets('1回目は installer を構築して返し、2回目は同じインスタンスを返す（memo）', (tester) async {
      final ssh = FakeSshClient();
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);
      final manifest = _testManifest();

      final installer1 = await composer.ensureInstaller(ssh, manifest);
      final installer2 = await composer.ensureInstaller(ssh, manifest);

      expect(
        identical(installer1, installer2),
        isTrue,
        reason: 'caret と hyperlink 読取で同じ installer インスタンスを共有すること',
      );
    });

    testWidgets('同時に呼ばれた ensureInstaller は single-flight で1つの構築に合流する', (
      tester,
    ) async {
      final ssh = FakeSshClient();
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);
      final manifest = _testManifest();

      final futures = [
        composer.ensureInstaller(ssh, manifest),
        composer.ensureInstaller(ssh, manifest),
        composer.ensureInstaller(ssh, manifest),
      ];
      final results = await Future.wait(futures);

      expect(identical(results[0], results[1]), isTrue);
      expect(identical(results[0], results[2]), isTrue);
    });

    testWidgets('別の SshClient（再接続相当）では memo を使い回さず新しい installer を構築する（'
        '接続単位で memoize する）', (tester) async {
      final ssh1 = FakeSshClient();
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh1));
      final composer = HerdrCaretComposer(host);
      final manifest = _testManifest();

      final installer1 = await composer.ensureInstaller(ssh1, manifest);

      // 再接続相当: 新しい SshClient で呼ぶ。
      final ssh2 = FakeSshClient();
      final installer2 = await composer.ensureInstaller(ssh2, manifest);

      expect(
        identical(installer1, installer2),
        isFalse,
        reason: '古い client に結びついた installer を使い回さないこと',
      );

      // 単一 slot の memo なので、client を ssh1 に戻すとまた作り直される
      // （ssh1 用の installer をキャッシュし続けているわけではない）。
      final installer1Again = await composer.ensureInstaller(ssh1, manifest);
      expect(identical(installer1Again, installer1), isFalse);
      expect(identical(installer1Again, installer2), isFalse);
    });

    testWidgets('再接続後は古い installer が caret 用・hyperlink 用のどちらにも返らない（'
        'caret（setupProduction）と hyperlink（setupHyperlinkProduction）'
        'は共に本メソッド 1 つだけを経由するため（herdr_caret.dart の '
        'setupProduction/setupHyperlinkProduction）、ここで「同一 client なら共有・'
        '別 client なら作り直し」を検証すれば両方の呼び出し元に伝播することを示す）', (tester) async {
      final ssh1 = FakeSshClient();
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh1));
      final composer = HerdrCaretComposer(host);
      final manifest = _testManifest();

      // caret 側・hyperlink 側それぞれの呼び出しを模す（同じ client）。
      final caretSideBefore = await composer.ensureInstaller(ssh1, manifest);
      final hyperlinkSideBefore = await composer.ensureInstaller(
        ssh1,
        manifest,
      );
      expect(
        identical(caretSideBefore, hyperlinkSideBefore),
        isTrue,
        reason: '再接続前は caret/hyperlink で共有される',
      );

      // 再接続相当。
      final ssh2 = FakeSshClient();
      final caretSideAfter = await composer.ensureInstaller(ssh2, manifest);
      final hyperlinkSideAfter = await composer.ensureInstaller(ssh2, manifest);

      expect(
        identical(caretSideAfter, hyperlinkSideAfter),
        isTrue,
        reason: '再接続後も caret/hyperlink で新しい installer を共有する',
      );
      expect(
        identical(caretSideAfter, caretSideBefore),
        isFalse,
        reason: '古い installer が caret 側に返らないこと',
      );
      expect(
        identical(hyperlinkSideAfter, caretSideBefore),
        isFalse,
        reason: '古い installer が hyperlink 側に返らないこと',
      );
    });
  });

  group('HerdrCaretComposer.setupHyperlinkProduction', () {
    testWidgets('設定 OFF では hyperlinkReader を構築しない', (tester) async {
      final ssh = FakeSshClient();
      final host = _FakeHerdrCaretHost(
        ref: await _pumpRefFor(
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
      final host = _FakeHerdrCaretHost(
        ref: await _pumpRefFor(
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
      final host = _FakeHerdrCaretHost(
        ref: await _pumpRefFor(
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
      final host = _FakeHerdrCaretHost(
        ref: await _pumpRefFor(
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
      final host = _FakeHerdrCaretHost(
        ref: await _pumpRefFor(
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
      final host = _FakeHerdrCaretHost(
        ref: await _pumpRefFor(
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
      final host = _FakeHerdrCaretHost(
        ref: await _pumpRefFor(
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
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
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
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
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
        final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
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
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
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
    // では到達できない（本ファイル 493-495 行目付近のコメント、および
    // terminal_screen_herdr_caret_test.dart 489-491 行目のコメントと同じ
    // 制約）。そのため、reader 代入は setupScrollbackLinkReader を経由せず
    // buildScrollbackLinkReader の直接呼び出しで模し、
    // onScrollbackLinkReaderAssigned（本番では setupScrollbackLinkReader
    // の成功パス・herdr_caret.dart 521 行目付近から呼ばれる）を直接呼んで
    // 「代入前に届いた settle が代入後に 1 回だけ再送される」核心部分を
    // 検証する。
    const identity = (identity: 'id-1', generation: 1);
    const lineCount = 2;
    const range = (top: 0, bottom: 1);

    Future<_FakeHerdrCaretHost> buildReadyHost(WidgetTester tester) async {
      final ssh = FakeSshClient();
      final host = _FakeHerdrCaretHost(ref: await _pumpRefFor(tester, ssh));
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
}

/// [paneId] に固定の [rect] を持つ 1 layout の snapshot を [HerdrSnapshotCache]
/// に投入して返す（[HerdrCaretComposer.currentScrollbackLinkPane]
/// テスト用。`HerdrCaretHelperManifest.load()` を経由しない検証方針は
/// 既存の [_testManifest] と同じ）。
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
