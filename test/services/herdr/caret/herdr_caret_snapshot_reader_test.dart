// inventory: HERDR-CARET-READER-TEST-000
/// herdr_caret_snapshot_reader.dart のテスト。
///
/// fake HerdrCaretHelperRunner を注入し、成功時キャッシュ・TTL 制御・
/// timeout/FormatException の null 化・epoch 変化時の stale 破棄・設定 OFF や
/// 非対応 protocol/socket で runner が呼ばれないことを検証する。
library;

import 'dart:async';

import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_manager.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_snapshot_reader.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_snapshot_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_ssh_client.dart';

/// [HerdrCaretHelperRunner] の fake。呼び出し回数・paneId・出力・例外・
/// 待機ゲートを差し替えられる。
class _FakeRunner implements HerdrCaretHelperRunner {
  int calls = 0;
  final List<String> paneIds = [];
  String stdout = _helperJson();
  Object? error;

  /// 設定時は [run] がこの完了まで待機する（in-flight 状態を作る）。
  Completer<void>? gate;

  @override
  Future<HerdrCaretHelperRunResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    Duration? timeout,
  }) async {
    calls++;
    paneIds.add(paneId);
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return HerdrCaretHelperRunResult(stdout: stdout, remotePath: '/x/helper');
  }
}

/// snapshot を返すだけの最小 adapter（epoch 加算用）。
class _MinimalAdapter extends HerdrAdapter {
  _MinimalAdapter() : super(FakeSshClient());

  @override
  Future<HerdrSnapshot> snapshot({Duration? timeout}) async =>
      const HerdrSnapshot(protocol: 17, version: 'test');
}

String _helperJson({String paneId = 'w1:p1'}) =>
    '{"cursor":{"x":3,"y":5,"visible":true,"shape":0},'
    '"frameWidth":80,"frameHeight":24,"protocolVersion":17,'
    '"paneId":"$paneId"}';

class _ReaderEnv {
  _ReaderEnv() {
    cache = HerdrSnapshotCache(() => _adapter, clock: () => now);
    reader = HerdrCaretHelperSnapshotReader(
      runner: runner,
      statusProvider: () => status,
      cacheProvider: () => cache,
      enabled: () => enabled,
      clock: () => now,
    );
  }

  final _FakeRunner runner = _FakeRunner();
  final _adapter = _MinimalAdapter();
  late HerdrSnapshotCache cache;
  late final HerdrCaretHelperSnapshotReader reader;

  HerdrStatus status = const HerdrStatus(
    serverProtocol: 17,
    socket: '/tmp/herdr.sock',
  );
  bool enabled = true;
  DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
}

void main() {
  group('成功時キャッシュ / TTL', () {
    test('成功時は snapshot を返し、TTL 内の再読では runner を呼ばない', () async {
      final env = _ReaderEnv();
      final s1 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s1, isNotNull);
      expect(s1!.paneId, 'w1:p1');
      expect(s1.x, 3);
      expect(s1.y, 5);
      expect(s1.visible, isTrue);
      expect(s1.protocolVersion, 17);
      expect(env.runner.calls, 1);

      env.now = env.now.add(const Duration(milliseconds: 100));
      final s2 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s2, isNotNull);
      expect(env.runner.calls, 1); // TTL 内はキャッシュ
      expect(env.reader.cachedSnapshot, isNotNull);
    });

    test('TTL を過ぎると runner が再度呼ばれる', () async {
      final env = _ReaderEnv();
      await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 1);

      env.now = env.now.add(const Duration(milliseconds: 600));
      final s2 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s2, isNotNull);
      expect(env.runner.calls, 2);
    });

    test('同一 pane の同時要求は single-flight で 1 回の実行に合流する', () async {
      final env = _ReaderEnv();
      final gate = Completer<void>();
      env.runner.gate = gate;
      final f1 = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      final f2 = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 1);
      gate.complete();
      final r1 = await f1;
      final r2 = await f2;
      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(env.runner.calls, 1);
    });

    test('異なる pane は合流せず個別に実行される', () async {
      final env = _ReaderEnv();
      final gate = Completer<void>();
      env.runner.gate = gate;
      final f1 = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      final f2 = env.reader.read(paneId: 'w1:p2', cols: 80, rows: 24);
      expect(env.runner.calls, 2);
      expect(env.runner.paneIds, ['w1:p1', 'w1:p2']);
      gate.complete();
      await f1;
      await f2;
      expect(env.runner.calls, 2);
    });
  });

  group('失敗したときは null を返す', () {
    test('timeout 例外は null を返しキャッシュしない', () async {
      final env = _ReaderEnv();
      env.runner.error = HerdrCaretHelperException(
        HerdrCaretHelperFailure.timeout,
        'timed out',
      );
      final s = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s, isNull);
      expect(env.reader.cachedSnapshot, isNull);
      expect(env.runner.calls, 1);
    });

    test('FormatException（破損 JSON）は null を返す', () async {
      final env = _ReaderEnv();
      env.runner.stdout = 'not json';
      final s = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s, isNull);
      expect(env.reader.cachedSnapshot, isNull);
    });

    test('helper 出力の paneId 不一致は null を返す（stale 破棄の最終防衛）', () async {
      final env = _ReaderEnv();
      env.runner.stdout = _helperJson(paneId: 'w1:p2');
      final s = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s, isNull);
      expect(env.reader.cachedSnapshot, isNull);
    });
  });

  group('epoch / stale 破棄', () {
    test('await 中に cache epoch が増えると in-flight 結果を破棄する（pane 切替相当）', () async {
      final env = _ReaderEnv();
      final gate = Completer<void>();
      env.runner.gate = gate;
      final future = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 1); // 実行は開始済み

      // pane 切替相当: 同一 cache で force 再取得 → epoch 0 → 1
      await env.cache.get(force: true);
      expect(env.cache.epoch, 1);

      gate.complete();
      final s = await future;
      expect(s, isNull); // stale 結果は破棄
      expect(env.reader.cachedSnapshot, isNull);
    });

    test('await 中に cache インスタンスが入れ替わると in-flight 結果を破棄する（再接続相当）', () async {
      final env = _ReaderEnv();
      final gate = Completer<void>();
      env.runner.gate = gate;
      final future = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 1);

      // adapter 差し替え（SSH 再接続）相当: キャッシュごと作り直す
      env.cache = HerdrSnapshotCache(() => _MinimalAdapter(), clock: () => env.now);

      gate.complete();
      final s = await future;
      expect(s, isNull);
      expect(env.reader.cachedSnapshot, isNull);
    });
  });

  group('実行しない条件', () {
    test('設定 OFF では runner を呼ばない', () async {
      final env = _ReaderEnv()..enabled = false;
      final s = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s, isNull);
      expect(env.runner.calls, 0);
    });

    test('protocol 18 では runner を呼ばない', () async {
      final env = _ReaderEnv();
      env.status = const HerdrStatus(serverProtocol: 18, socket: '/tmp/herdr.sock');
      final s = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s, isNull);
      expect(env.runner.calls, 0);
    });

    test('socket が無ければ runner を呼ばない', () async {
      final env = _ReaderEnv();
      env.status = const HerdrStatus(serverProtocol: 17);
      final s = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s, isNull);
      expect(env.runner.calls, 0);
    });

    test('statusProvider が例外を投げても runner を呼ばない', () async {
      final env = _ReaderEnv();
      final throwingReader = HerdrCaretHelperSnapshotReader(
        runner: env.runner,
        statusProvider: () => throw StateError('no status'),
        cacheProvider: () => env.cache,
        enabled: () => true,
      );
      final s = await throwingReader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(s, isNull);
      expect(env.runner.calls, 0);
    });
  });
}