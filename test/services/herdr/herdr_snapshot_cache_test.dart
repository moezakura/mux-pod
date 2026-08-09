import 'dart:async';

import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_snapshot_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ssh_client.dart';

HerdrSnapshot _snap(String tag) => HerdrSnapshot(
      protocol: 17,
      version: tag,
      focusedPaneId: 'w1:p1',
      workspaces: const [HerdrWorkspace(id: 'w1', label: 'ws', number: 1)],
      tabs: const [HerdrTab(id: 'w1:t1', workspaceId: 'w1', label: '1', number: 1)],
      panes: const [HerdrPane(id: 'w1:p1', workspaceId: 'w1', tabId: 'w1:t1')],
    );

/// [HerdrAdapter] の snapshot を差し替え可能にした fake。
///
/// インスタンス毎に identity が異なるため、`identical` での adapter 差し替え
/// 検出（再接続相当）をテストできる。
class _FakeSnapshotAdapter extends HerdrAdapter {
  _FakeSnapshotAdapter(this._responses, {this.gate}) : super(FakeSshClient());

  final List<HerdrSnapshot> _responses;
  final Completer<void>? gate;
  int snapshotCalls = 0;

  @override
  Future<HerdrSnapshot> snapshot({Duration? timeout}) async {
    snapshotCalls++;
    if (gate != null) await gate!.future;
    final index = snapshotCalls - 1;
    return _responses[index >= _responses.length ? _responses.length - 1 : index];
  }
}

void main() {
  group('HerdrSnapshotCache TTL', () {
    test('TTL 内はキャッシュを返し adapter.snapshot を呼ばない', () async {
      final adapter = _FakeSnapshotAdapter([_snap('a')]);
      final cache = HerdrSnapshotCache(() => adapter, ttl: const Duration(seconds: 5));

      final first = await cache.get();
      expect(first.version, 'a');
      expect(adapter.snapshotCalls, 1);
      expect(cache.epoch, 0); // 初回取得は増分対象外（force/adapter差し替えのみ）

      final second = await cache.get();
      expect(identical(first, second), isTrue);
      expect(adapter.snapshotCalls, 1);
      expect(cache.epoch, 0); // キャッシュ返却ではエポック不変
    });

    test('TTL 切れで再取得する（エポックは増えない）', () async {
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final adapter = _FakeSnapshotAdapter([_snap('a'), _snap('b')]);
      final cache = HerdrSnapshotCache(
        () => adapter,
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );

      final first = await cache.get();
      expect(first.version, 'a');
      expect(adapter.snapshotCalls, 1);

      now = now.add(const Duration(seconds: 6)); // TTL 超過
      final second = await cache.get();
      expect(second.version, 'b');
      expect(adapter.snapshotCalls, 2);
      // TTL 切れの通常再取得は表示対象を変えないためエポック不変
      expect(cache.epoch, 0);
    });

    test('TTL 注入が効く（短い TTL で即再取得）', () async {
      final adapter = _FakeSnapshotAdapter([_snap('a'), _snap('b')]);
      final cache = HerdrSnapshotCache(
        () => adapter,
        ttl: const Duration(milliseconds: 1),
      );
      await cache.get();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await cache.get();
      expect(second.version, 'b');
      expect(adapter.snapshotCalls, 2);
    });
  });

  group('HerdrSnapshotCache forceFresh', () {
    test('force: true で TTL 内でも再取得しエポック++ する', () async {
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final adapter = _FakeSnapshotAdapter([_snap('a'), _snap('b')]);
      final cache = HerdrSnapshotCache(
        () => adapter,
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );

      await cache.get();
      expect(cache.epoch, 0);

      final forced = await cache.get(force: true);
      expect(forced.version, 'b');
      expect(adapter.snapshotCalls, 2);
      expect(cache.epoch, 1); // force はエポック++
    });
  });

  group('HerdrSnapshotCache single-flight', () {
    test('同時呼び出しは 1 回の snapshot 実行にまとまる', () async {
      final gate = Completer<void>();
      final adapter = _FakeSnapshotAdapter([_snap('a')], gate: gate);
      final cache = HerdrSnapshotCache(() => adapter);

      final f1 = cache.get();
      final f2 = cache.get();
      final f3 = cache.get();

      gate.complete();
      final results = await Future.wait([f1, f2, f3]);

      expect(adapter.snapshotCalls, 1);
      expect(results.every((r) => r.version == 'a'), isTrue);
    });
  });

  group('HerdrSnapshotCache adapter swap (identical 検出)', () {
    test('adapter 差し替えで自動再取得＋エポック++ する', () async {
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final adapterA = _FakeSnapshotAdapter([_snap('a')]);
      final adapterB = _FakeSnapshotAdapter([_snap('b')]);
      var current = adapterA;
      final cache = HerdrSnapshotCache(
        () => current,
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );

      final first = await cache.get();
      expect(first.version, 'a');
      expect(adapterA.snapshotCalls, 1);
      expect(cache.epoch, 0);

      // 再接続相当: adapter インスタンスが差し替わる
      current = adapterB;
      final second = await cache.get();
      expect(second.version, 'b');
      expect(adapterB.snapshotCalls, 1);
      expect(adapterA.snapshotCalls, 1); // A は再呼び出しされない
      expect(cache.epoch, 1); // 差し替え検出でエポック++
    });

    test('無差し替えならキャッシュ返却でエポック不変', () async {
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final adapter = _FakeSnapshotAdapter([_snap('a')]);
      final cache = HerdrSnapshotCache(
        () => adapter,
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );

      await cache.get();
      expect(cache.epoch, 0);

      final again = await cache.get();
      expect(again.version, 'a');
      expect(adapter.snapshotCalls, 1);
      expect(cache.epoch, 0); // 差し替えなし + TTL 内 → エポック不変
    });
  });

  group('HerdrSnapshotCache invalidate', () {
    test('invalidate 後は次回 get で再取得する', () async {
      final adapter = _FakeSnapshotAdapter([_snap('a'), _snap('b')]);
      final cache = HerdrSnapshotCache(() => adapter, ttl: const Duration(seconds: 5));

      await cache.get();
      expect(cache.hasSnapshot, isTrue);
      expect(adapter.snapshotCalls, 1);

      cache.invalidate(); // server-down 時の失効相当
      expect(cache.hasSnapshot, isFalse);

      final again = await cache.get();
      expect(again.version, 'b');
      expect(adapter.snapshotCalls, 2);
      // 失効自体は表示対象の切替ではないためエポック不変
      expect(cache.epoch, 0);
    });
  });
}
