// inventory: HERDR-HYPERLINK-READER-TEST-000
/// herdr_hyperlink_reader.dart のテスト（herdr OSC 8 ハイパーリンク実験
/// 機能）。
///
/// fake HerdrHyperlinkHelperRunner を注入し、成功時キャッシュ・TTL 制御・
/// single-flight・失敗時の null 化・epoch 変化時の stale 破棄・設定
/// OFF や非対応 protocol/socket・status 未確立で runner が呼ばれないこと
/// （poll ごとの SSH 実行回数を既存 caret と同じ 0 回に保つ）を
/// 検証する。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart';
import 'package:flutter_muxpod/services/herdr/caret/herdr_caret_helper_types.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_snapshot_cache.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_helper_manager.dart';
import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_ssh_client.dart';

/// [HerdrHyperlinkHelperRunner] の fake。呼び出し回数・paneId・結果・例外・
/// 待機ゲートを差し替えられる。
class _FakeRunner implements HerdrHyperlinkHelperRunner {
  int calls = 0;
  final List<String> paneIds = [];
  PaneHyperlinks result = _hyperlinks();
  Object? error;

  /// 設定時は [run] がこの完了まで待機する（in-flight 状態を作る）。
  Completer<void>? gate;

  @override
  Future<PaneHyperlinks> run({
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
    return result;
  }
}

/// snapshot を返すだけの最小 adapter（epoch 加算用）。
class _MinimalAdapter extends HerdrAdapter {
  _MinimalAdapter() : super(FakeSshClient());

  @override
  Future<HerdrSnapshot> snapshot({Duration? timeout}) async =>
      const HerdrSnapshot(protocol: 17, version: 'test');
}

PaneHyperlinks _hyperlinks({int frameWidth = 80, int frameHeight = 24}) =>
    PaneHyperlinks(
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      links: const [
        PaneHyperlink(
          url: 'https://example.com/',
          ranges: [PaneHyperlinkRange(row: 3, startCol: 10, endCol: 24)],
        ),
      ],
      rowFingerprints: const {3: '9f1c000000000000'},
    );

class _ReaderEnv {
  _ReaderEnv() {
    cache = HerdrSnapshotCache(() => _adapter, clock: () => now);
    reader = HerdrHyperlinkHelperReader(
      runner: runner,
      statusProvider: () => status,
      cacheProvider: () => disposed ? null : cache,
      enabled: () => enabled,
      clock: () => now,
    );
  }

  final _FakeRunner runner = _FakeRunner();
  final _adapter = _MinimalAdapter();
  late HerdrSnapshotCache cache;
  late final HerdrHyperlinkHelperReader reader;

  HerdrStatus status = const HerdrStatus(
    serverProtocol: 17,
    socket: '/tmp/herdr.sock',
  );
  bool enabled = true;

  /// true の間 cacheProvider は null を返す（画面破棄後の `_snapshotCache = null` 相当）。
  bool disposed = false;
  DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
}

void main() {
  group('成功時キャッシュ / TTL', () {
    test('成功時は PaneHyperlinks を返し、TTL 内の再読では runner を呼ばない', () async {
      final env = _ReaderEnv();
      final r1 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r1, isNotNull);
      expect(r1!.frameWidth, 80);
      expect(r1.links, hasLength(1));
      expect(env.runner.calls, 1);

      env.now = env.now.add(const Duration(milliseconds: 100));
      final r2 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r2, isNotNull);
      expect(env.runner.calls, 1); // TTL 内はキャッシュ
      expect(env.reader.cachedHyperlinks, isNotNull);
    });

    test('TTL を過ぎると runner が再度呼ばれる', () async {
      final env = _ReaderEnv();
      await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 1);

      env.now = env.now.add(const Duration(milliseconds: 600));
      final r2 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r2, isNotNull);
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

    test('TTL 内でも別の pane では runner を呼ぶ（キャッシュを使わない。'
        '_cachedPaneId 照合）', () async {
      final env = _ReaderEnv();
      await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 1);

      env.now = env.now.add(const Duration(milliseconds: 100)); // TTL 内
      final r2 = await env.reader.read(paneId: 'w1:p2', cols: 80, rows: 24);
      expect(r2, isNotNull);
      expect(env.runner.calls, 2); // pane1 のキャッシュを使い回さない
      expect(env.runner.paneIds, ['w1:p1', 'w1:p2']);
    });
  });

  group('失敗したときは null を返す', () {
    test('timeout 例外は null を返しキャッシュしない', () async {
      final env = _ReaderEnv();
      env.runner.error = HerdrCaretHelperException(
        HerdrCaretHelperFailure.timeout,
        'timed out',
      );
      final r = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNull);
      expect(env.reader.cachedHyperlinks, isNull);
      expect(env.runner.calls, 1);
    });

    test('未対応 protocol（unsupportedProtocol）は null を返す', () async {
      final env = _ReaderEnv();
      env.runner.error = HerdrCaretHelperException(
        HerdrCaretHelperFailure.unsupportedProtocol,
        'unsupported',
      );
      final r = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNull);
      expect(env.reader.cachedHyperlinks, isNull);
    });

    test('その他の例外も null を返す', () async {
      final env = _ReaderEnv();
      env.runner.error = StateError('boom');
      final r = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNull);
      expect(env.reader.cachedHyperlinks, isNull);
    });
  });

  group('epoch / stale 破棄（通常表示のずれ抑制ルール）', () {
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
      final r = await future;
      expect(r, isNull); // stale 結果は破棄
      expect(env.reader.cachedHyperlinks, isNull);
    });

    test('await 中に cache インスタンスが入れ替わると in-flight 結果を破棄する（再接続相当）', () async {
      final env = _ReaderEnv();
      final gate = Completer<void>();
      env.runner.gate = gate;
      final future = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 1);

      // adapter 差し替え（SSH 再接続）相当: キャッシュごと作り直す
      env.cache = HerdrSnapshotCache(
        () => _MinimalAdapter(),
        clock: () => env.now,
      );

      gate.complete();
      final r = await future;
      expect(r, isNull);
      expect(env.reader.cachedHyperlinks, isNull);
    });
  });

  group('破棄後の扱い（snapshotCache が null になった後）', () {
    /// debugPrint の出力を集めて返す（終了時に元へ戻す）。
    Future<List<String>> captureLogs(Future<void> Function() body) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await body();
      } finally {
        debugPrint = original;
      }
      return logs;
    }

    test(
      'in-flight 中に cache が破棄され run が正常に返ると null を返し invalid を記録しない',
      () async {
        final env = _ReaderEnv();
        final gate = Completer<void>();
        env.runner.gate = gate;
        PaneHyperlinks? result = _hyperlinks();
        final logs = await captureLogs(() async {
          final future = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
          expect(env.runner.calls, 1);
          env.disposed = true; // 画面破棄: snapshotCache = null
          gate.complete();
          result = await future;
        });
        expect(result, isNull);
        expect(env.reader.cachedHyperlinks, isNull);
        expect(logs.where((l) => l.contains('invalid')), isEmpty);
        expect(
          logs.where((l) => l.contains('[herdr-hyperlink] disposed')),
          hasLength(1),
        );
      },
    );

    test('破棄済み（cacheProvider が null）では runner を呼ばず null を返す', () async {
      final env = _ReaderEnv();
      env.disposed = true;
      PaneHyperlinks? result = _hyperlinks();
      final logs = await captureLogs(() async {
        result = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      });
      expect(result, isNull);
      expect(env.runner.calls, 0);
      expect(logs.where((l) => l.contains('invalid')), isEmpty);
    });

    test('破棄後に run が HerdrCaretHelperException を投げても従来どおり分類ログを記録する', () async {
      final env = _ReaderEnv();
      final gate = Completer<void>();
      env.runner.gate = gate;
      env.runner.error = HerdrCaretHelperException(
        HerdrCaretHelperFailure.timeout,
        'timed out',
      );
      PaneHyperlinks? result = _hyperlinks();
      final logs = await captureLogs(() async {
        final future = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
        env.disposed = true;
        gate.complete();
        result = await future;
      });
      expect(result, isNull);
      expect(
        logs.where((l) => l.contains('[herdr-hyperlink] timeout')),
        hasLength(1),
      );
      expect(logs.where((l) => l.contains('invalid')), isEmpty);
    });

    test('破棄後に完了しても _inFlight は除去され、再度 read できる', () async {
      final env = _ReaderEnv();
      final gate = Completer<void>();
      env.runner.gate = gate;
      final future = env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      env.disposed = true;
      gate.complete();
      expect(await future, isNull);
      await Future<void>.delayed(Duration.zero); // whenComplete の除去を待つ

      env.disposed = false;
      env.runner.gate = null;
      final r = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNotNull);
      expect(env.runner.calls, 2); // 合流せず新規実行
    });
  });

  group('実行しない条件（設定 OFF で SSH 0 回・status 未確立でも 0 回）', () {
    test('設定 OFF では runner を呼ばない', () async {
      final env = _ReaderEnv()..enabled = false;
      final r = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNull);
      expect(env.runner.calls, 0);
    });

    test('protocol 18（未対応）では runner を呼ばない', () async {
      final env = _ReaderEnv();
      env.status = const HerdrStatus(
        serverProtocol: 18,
        socket: '/tmp/herdr.sock',
      );
      final r = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNull);
      expect(env.runner.calls, 0);
    });

    test('socket が無ければ runner を呼ばない', () async {
      final env = _ReaderEnv();
      env.status = const HerdrStatus(serverProtocol: 17);
      final r = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNull);
      expect(env.runner.calls, 0);
    });

    test('statusProvider が例外を投げても runner を呼ばない', () async {
      final env = _ReaderEnv();
      final throwingReader = HerdrHyperlinkHelperReader(
        runner: env.runner,
        statusProvider: () => throw StateError('no status'),
        cacheProvider: () => env.cache,
        enabled: () => true,
      );
      final r = await throwingReader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r, isNull);
      expect(env.runner.calls, 0);
    });

    test('status 未確立（既定値 HerdrStatus()）が pollごとに複数回渡されても '
        'runner は 1 回も呼ばれない（caret と同じ 0 回。ensureStatus の再試行は '
        'reader の責務外）', () async {
      final env = _ReaderEnv();
      env.status = const HerdrStatus(); // serverProtocol 既定値（未確立扱い）
      // poll 相当で複数回 read を呼んでも SSH（runner）は 0 回のまま。
      await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(env.runner.calls, 0);
    });

    test('キャッシュ済み（TTL 内）でも設定 OFF に切り替えると null を返す（'
        'runner は呼ばない）', () async {
      final env = _ReaderEnv();
      final r1 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r1, isNotNull);
      expect(env.runner.calls, 1);

      env.enabled = false;
      env.now = env.now.add(const Duration(milliseconds: 100)); // TTL 内
      final r2 = await env.reader.read(paneId: 'w1:p1', cols: 80, rows: 24);
      expect(r2, isNull); // OFF に切り替えたら TTL 内キャッシュも出さない
      expect(env.runner.calls, 1); // runner は追加で呼ばれない
    });
  });
}
