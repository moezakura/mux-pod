import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_resize_bridge.dart';
import 'package:flutter_muxpod/services/herdr/herdr_snapshot_cache.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import '../../helpers/fake_ssh_client.dart';

/// [ManagedPtyProcess] の fake（implements は public API のみ実装でよい）。
class _FakeManagedPty implements ManagedPtyProcess {
  final StreamController<void> _doneController =
      StreamController<void>.broadcast();
  final List<(int, int)> resizes = [];
  final List<String> closeLog = [];
  bool throwOnResize = false;
  bool emitDoneOnClose = true;
  String command = '';
  ({int cols, int rows})? initialSize;

  @override
  Stream<void> get done => _doneController.stream;

  @override
  int? get exitCode => null;

  @override
  String? get exitSignalName => null;

  @override
  String get stderrTail => '';

  @override
  void resize(int cols, int rows) {
    if (throwOnResize) throw StateError('resize failed');
    resizes.add((cols, rows));
  }

  @override
  Future<void> close() async {
    closeLog.add('close');
    if (emitDoneOnClose && !_doneController.isClosed) {
      _doneController.add(null);
    }
  }

  void emitDone() {
    if (!_doneController.isClosed) _doneController.add(null);
  }
}

/// [SshClient.startManagedPty] をオーバーライドした fake。
class _FakeResizeClient extends FakeSshClient {
  final List<_FakeManagedPty> processes = [];
  bool failStart = false;
  String? lastCommand;
  ({int cols, int rows})? lastStartSize;

  @override
  Future<ManagedPtyProcess> startManagedPty(
    String command, {
    required int cols,
    required int rows,
  }) async {
    lastCommand = command;
    lastStartSize = (cols: cols, rows: rows);
    if (failStart) throw StateError('start failed');
    final p = _FakeManagedPty();
    p.command = command;
    p.initialSize = (cols: cols, rows: rows);
    processes.add(p);
    return p;
  }
}

/// [HerdrSnapshotCache.get] を制御する fake。
class _FakeCache extends HerdrSnapshotCache {
  _FakeCache() : super(() => throw UnimplementedError());

  final List<({bool force, bool joinInflight})> getLog = [];
  HerdrSnapshot Function()? snapshotProvider;
  HerdrSnapshot Function()? onGet;
  HerdrSnapshot? fixedSnapshot;

  @override
  Future<HerdrSnapshot> get({
    bool force = false,
    bool joinInflight = true,
  }) async {
    getLog.add((force: force, joinInflight: joinInflight));
    if (onGet != null) return onGet!();
    if (snapshotProvider != null) return snapshotProvider!();
    return fixedSnapshot ?? snapshot(width: 0, height: 0);
  }
}

HerdrSnapshot snapshot({
  required int width,
  required int height,
  String tabId = 'w1:t1',
}) {
  return HerdrSnapshot(
    protocol: 17,
    version: '0.8.0',
    focusedTabId: tabId,
    layouts: [
      HerdrLayout(
        area: HerdrRect(width: width, height: height),
        tabId: tabId,
      ),
    ],
  );
}

HerdrResizeBridge _bridge({
  required _FakeResizeClient client,
  required _FakeCache cache,
  String executablePath = '/lab/herdr',
  String? tabId = 'w1:t1',
  Duration? convergeTimeout,
  Duration? convergePollInterval,
}) {
  return HerdrResizeBridge(
    client: client,
    cache: cache,
    executablePath: executablePath,
    tabIdProvider: () => tabId,
    convergeTimeout: convergeTimeout,
    convergePollInterval: convergePollInterval,
  );
}

void main() {
  group('HerdrResizeBridge', () {
    test('resize 成功: 実測変換式（cols-26 / rows-1）で収束確認し true を返す', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      // currentPtySize（初回・ensureStarted 前）: area 74x29 → PTY 100x30 を推定。
      // 収束確認（joinInflight:false の fresh）: area 94x39 = 120-26 / 40-1。
      cache.onGet = () {
        final last = cache.getLog.last;
        if (!last.joinInflight) return snapshot(width: 94, height: 39);
        return snapshot(width: 74, height: 29);
      };
      final bridge = _bridge(client: client, cache: cache);

      final current = await bridge.currentPtySize();
      expect(current.cols, 100);
      expect(current.rows, 30);

      final ok = await bridge.resize(120, 40);
      expect(ok, isTrue);
      // 起動時 Hello = 現在の PTY 要求サイズ（100x30・他クライアントのサイズを
      // 上書きしない・lazy start）。
      expect(client.lastStartSize, (cols: 100, rows: 30));
      // resize は 120x40 を送る。
      expect(client.processes.single.resizes, contains((120, 40)));
      // 収束確認は fresh snapshot（force + joinInflight:false）で area == 94x39。
      final converged = cache.getLog.any((l) => l.force && !l.joinInflight);
      expect(converged, isTrue);
    });

    test('ダイアログ初期値は Bridge 保持の現在 PTY 要求サイズ（自己縮小バグ回避）', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(
        client: client,
        cache: cache,
        // resize が収束しない（74x29 のまま）ためタイムアウトまで実待ちしない
        // よう短縮（プロダクション値は別テストで担保）。
        convergeTimeout: const Duration(milliseconds: 150),
        convergePollInterval: const Duration(milliseconds: 20),
      );

      await bridge.currentPtySize(); // 初回: area 逆算 100x30
      await bridge.resize(120, 40); // 成功後: 120x40 を保持

      // resize 後の currentPtySize は「保持された 120x40」（area 逆算に戻らない）。
      final next = await bridge.currentPtySize();
      expect(next.cols, 120);
      expect(next.rows, 40);
    });

    test('収束しない（area が期待値と不一致）場合はポーリング継続後タイムアウトで false', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(
        client: client,
        cache: cache,
        // タイムアウトまで実待ちしないよう短縮（プロダクション値は別テストで担保）。
        convergeTimeout: const Duration(milliseconds: 150),
        convergePollInterval: const Duration(milliseconds: 20),
      );

      // resize 後も area が 74x29 のまま（期待 94x39）→ 収束せず false。
      final ok = await bridge.resize(120, 40);
      expect(ok, isFalse);
      // 初回ポーリングの即時 fail ではないこと（複数回ポーリングしてから false）。
      final convergenceGets = cache.getLog.where((l) => !l.joinInflight);
      expect(
        convergenceGets.length,
        greaterThanOrEqualTo(2),
        reason: '即時 fail せずポーリングを継続すること（5 秒間・ユーザー決定）',
      );
    });

    test('乖離 area（非デフォルト表示設定の兆候）でも即時 fail せずポーリング後 false', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      // resize 後の area が期待値（94x39）から大きく乖離（width: 10）しても、
      // 即時 fail せずポーリングを継続し、タイムアウト後に false。
      cache.onGet = () {
        final last = cache.getLog.last;
        if (!last.joinInflight) return snapshot(width: 10, height: 39);
        return snapshot(width: 74, height: 29);
      };
      final bridge = _bridge(
        client: client,
        cache: cache,
        convergeTimeout: const Duration(milliseconds: 150),
        convergePollInterval: const Duration(milliseconds: 20),
      );

      final ok = await bridge.resize(120, 40);
      expect(ok, isFalse);
      final convergenceGets = cache.getLog.where((l) => !l.joinInflight);
      expect(
        convergenceGets.length,
        greaterThanOrEqualTo(2),
        reason: '乖離 area でも初回ポーリングで即時 fail しない（daemon 適用遅延）',
      );
    });

    test('0 列 0 行・chrome 差引後 0 以下は拒否', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(client: client, cache: cache);

      expect(await bridge.resize(0, 0), isFalse);
      expect(await bridge.resize(26, 1), isFalse); // 差引後 0
      expect(await bridge.resize(25, 40), isFalse); // cols 差引後 -1
      expect(client.processes, isEmpty);
    });

    test('resize 失敗（ManagedPtyProcess.resize が throw）は false', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(client: client, cache: cache);

      // 起動成功後に resize が throw するよう仕込む（真の throw 経路）。
      await bridge.ensureStarted();
      client.processes.last.throwOnResize = true;

      final ok = await bridge.resize(120, 40);
      expect(ok, isFalse);
      // throw 経路は収束ループに入らず即 false（収束確認 get は実行されない）。
      final convergenceGets = cache.getLog.where((l) => !l.joinInflight);
      expect(convergenceGets, isEmpty);
    });

    test('start 失敗（executablePath 不正）は false（state failed）', () async {
      final client = _FakeResizeClient()..failStart = true;
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(client: client, cache: cache);

      final ok = await bridge.resize(120, 40);
      expect(ok, isFalse);
    });

    test('二重 ensureStarted は single-flight（旧 process を close）', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(client: client, cache: cache);

      await bridge.ensureStarted();
      await bridge.ensureStarted();
      // startManagedPty は二重起動を防ぐ（SshClient 側で旧を close・fake では
      // 新しいプロセスを返す）。
      expect(client.processes.length, greaterThanOrEqualTo(1));
    });

    test('resize 成功 → TUI 終了 → 自動再起動 → 最新要求サイズを再適用し収束する', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.onGet = () {
        final last = cache.getLog.last;
        if (!last.joinInflight) return snapshot(width: 94, height: 39);
        return snapshot(width: 74, height: 29);
      };
      final bridge = _bridge(client: client, cache: cache);

      final ok = await bridge.resize(120, 40);
      expect(ok, isTrue);
      expect(client.processes, hasLength(1));

      // TUI 単体終了（done）→ 自動再起動（限定回数内）→ 最新要求（120x40）を
      // 一度だけ再適用し、収束確認が走る（承認条件 6・世代チェックの回帰防止）。
      client.processes.first.emitDone();
      await pumpEventQueue();
      expect(
        client.processes.length,
        greaterThanOrEqualTo(2),
        reason: 'TUI 単体終了後は managed PTY が再起動されること',
      );
      final restarted = client.processes.last;
      expect(
        restarted.resizes,
        contains((120, 40)),
        reason: '再起動後に最新要求サイズ（120x40）が一度だけ再適用されること',
      );
      expect(bridge.stateForTesting, 'ready');
    });

    test('TUI 単体終了 → 限定再起動（初回を除く 3 回）→ 4 回目は failed', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(client: client, cache: cache);

      await bridge.ensureStarted();
      expect(bridge.stateForTesting, 'ready');

      // 3 回の再起動（done → 再起動 → done → ...）を許容する。
      for (var i = 0; i < 3; i++) {
        client.processes.last.emitDone();
        await Future<void>.delayed(Duration.zero);
        // 再起動が走る（ensureStarted を再呼び出し）。
        await bridge.ensureStarted();
        expect(bridge.stateForTesting, 'ready');
      }
      // 4 回目の done → 再起動回数超過 → failed。
      client.processes.last.emitDone();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.stateForTesting, 'failed');
    });

    test('reset は intentional close（再起動回数を消費しない・old done は無視）', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(client: client, cache: cache);

      await bridge.ensureStarted();
      await bridge.reset();
      expect(bridge.stateForTesting, 'idle');
      // reset 後の旧 process の done は世代不一致で無視され、再起動しない。
      client.processes.last.emitDone();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.stateForTesting, 'idle');
      // reset 後に再起動しても再起動回数は 0 から（初回扱い）。
      await bridge.ensureStarted();
      expect(bridge.stateForTesting, 'ready');
    });

    test('executablePath が startManagedPty に渡る', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29);
      final bridge = _bridge(
        client: client,
        cache: cache,
        executablePath: "'/path with space/herdr'",
      );

      await bridge.ensureStarted();
      expect(client.lastCommand, "'/path with space/herdr'");
    });

    test(
      '収束確認は joinInflight:false（window-change 送信後に開始された fetch を保証）',
      () async {
        final client = _FakeResizeClient();
        final cache = _FakeCache();
        cache.snapshotProvider = () => snapshot(width: 74, height: 29);
        final bridge = _bridge(
          client: client,
          cache: cache,
          // 収束しない（74x29 のまま）ためタイムアウトまで実待ちしないよう短縮。
          convergeTimeout: const Duration(milliseconds: 150),
          convergePollInterval: const Duration(milliseconds: 20),
        );

        await bridge.resize(120, 40);
        final convergenceGets = cache.getLog.where((l) => !l.joinInflight);
        expect(convergenceGets, isNotEmpty);
        expect(convergenceGets.every((l) => l.force), isTrue);
      },
    );

    test('matchesRequestedArea は実測変換式（width/height 個別比較）', () {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      final bridge = _bridge(client: client, cache: cache);
      expect(
        bridge.matchesRequestedArea(HerdrRect(width: 94, height: 39), 120, 40),
        isTrue,
      );
      expect(
        bridge.matchesRequestedArea(HerdrRect(width: 94, height: 40), 120, 40),
        isFalse,
      );
    });

    test('初回ポーリングで旧サイズを観測しても、ポーリング継続で収束すれば true', () async {
      // 本バグの回帰テスト: herdr daemon の適用遅延（30〜150ms）を模擬し、
      // 最初の 2 回の収束確認ポーリングは旧サイズ（74x29 = 乖離相当）、3 回目
      // 以降は新サイズ（94x39 = 120-26 / 40-1）を返す。即時 fail せず収束すること。
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      var convergencePolls = 0;
      cache.onGet = () {
        final last = cache.getLog.last;
        if (!last.joinInflight) {
          convergencePolls++;
          if (convergencePolls < 3) return snapshot(width: 74, height: 29);
          return snapshot(width: 94, height: 39);
        }
        return snapshot(width: 74, height: 29);
      };
      final bridge = _bridge(
        client: client,
        cache: cache,
        convergeTimeout: const Duration(milliseconds: 500),
        convergePollInterval: const Duration(milliseconds: 20),
      );

      final ok = await bridge.resize(120, 40);
      expect(ok, isTrue);
      final convergenceGets = cache.getLog.where((l) => !l.joinInflight);
      expect(
        convergenceGets.length,
        greaterThanOrEqualTo(3),
        reason: '旧サイズ観測後もポーリングを継続して収束すること（本バグの回帰防止）',
      );
    });

    test('resize 収束確認中に reset が割り込むと、タイムアウト前に false で返る', () async {
      final client = _FakeResizeClient();
      final cache = _FakeCache();
      cache.snapshotProvider = () => snapshot(width: 74, height: 29); // 収束しない
      final bridge = _bridge(
        client: client,
        cache: cache,
        convergeTimeout: const Duration(seconds: 5),
        convergePollInterval: const Duration(milliseconds: 50),
      );

      final stopwatch = Stopwatch()..start();
      final okFuture = bridge.resize(120, 40);
      // resize の収束ループ実行中に reset（世代が進む）を割り込ませる。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await bridge.reset();
      final ok = await okFuture;
      stopwatch.stop();

      expect(ok, isFalse);
      // 閾値は convergePollInterval 基準（正常時 ≈50ms で返るため 500ms で十分余裕）。
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(milliseconds: 500)),
        reason: 'gen 不一致はタイムアウト（5s）を待たず即時 false（安全弁）',
      );
    });

    test('収束確認の既定値は 100ms 間隔・5 秒タイムアウト（プロダクション方針）', () {
      expect(
        HerdrResizeBridge.defaultConvergePollInterval,
        const Duration(milliseconds: 100),
        reason: 'ユーザー決定: 100ms 間隔で変更適用をチェックする',
      );
      expect(
        HerdrResizeBridge.defaultConvergeTimeout,
        const Duration(seconds: 5),
        reason: 'ユーザー決定: 最大 5 秒でタイムアウトする',
      );
    });
  });
}
