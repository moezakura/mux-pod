import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/active_session.dart';
import 'package:flutter_muxpod/providers/active_sessions_merger.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';

void main() {
  group('ActiveSessionsMerger', () {
    final merger = ActiveSessionsMerger();
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    ActiveSession legacySession({
      required String connectionId,
      required String sessionName,
      DateTime? connectedAt,
      DateTime? lastAccessedAt,
      int? lastWindowIndex,
      String? lastPaneId,
    }) {
      return ActiveSession(
        connectionId: connectionId,
        connectionName: 'Conn-$connectionId',
        host: 'host-$connectionId',
        sessionName: sessionName,
        windowCount: 1,
        connectedAt: connectedAt ?? DateTime(2025, 1, 1),
        lastAccessedAt: lastAccessedAt,
        lastWindowIndex: lastWindowIndex,
        lastPaneId: lastPaneId,
      );
    }

    MultiplexerSession domainSession(
      String name, {
      String? id,
      int windowCount = 2,
      bool attached = true,
    }) {
      return MultiplexerSession(
        name: name,
        id: id,
        windowCount: windowCount,
        attached: attached,
      );
    }

    test('keeps sessions of other connections untouched', () {
      final current = [
        legacySession(connectionId: 'c1', sessionName: 'main'),
        legacySession(connectionId: 'c2', sessionName: 'other'),
      ];
      final merged = merger.merge(
        currentSessions: current,
        connectionId: 'c1',
        connectionName: 'Conn-c1',
        host: 'host-c1',
        sessions: [domainSession('main', id: 's0')],
        now: now,
      );
      expect(merged, hasLength(2));
      expect(
        merged.any((s) => s.connectionId == 'c2' && s.sessionName == 'other'),
        isTrue,
      );
      expect(
        merged.any((s) => s.connectionId == 'c1' && s.sessionId == 's0'),
        isTrue,
      );
    });

    test('replaces existing entry by id key and preserves history', () {
      final current = [
        legacySession(
          connectionId: 'c1',
          sessionName: 'main',
          connectedAt: DateTime(2025, 2, 1),
          lastAccessedAt: DateTime(2025, 3, 1),
          lastWindowIndex: 2,
          lastPaneId: '%5',
        ),
      ];
      final merged = merger.merge(
        currentSessions: current,
        connectionId: 'c1',
        connectionName: 'Conn-c1',
        host: 'host-c1',
        sessions: [domainSession('main', id: 's0', windowCount: 3)],
        now: now,
      );
      expect(merged, hasLength(1));
      final s = merged.single;
      expect(s.sessionId, 's0');
      expect(s.connectedAt, DateTime(2025, 2, 1));
      expect(s.lastAccessedAt, DateTime(2025, 3, 1));
      expect(s.lastWindowIndex, 2);
      expect(s.lastPaneId, '%5');
      expect(s.windowCount, 3);
    });

    test('new session without existing entry uses provided now', () {
      final merged = merger.merge(
        currentSessions: const [],
        connectionId: 'c1',
        connectionName: 'Conn-c1',
        host: 'host-c1',
        sessions: [domainSession('main', id: 's0')],
        now: now,
      );
      expect(merged.single.connectedAt, now);
      expect(merged.single.lastAccessedAt, isNull);
    });

    test('adopts unique legacy sessionId-null entry by matching label', () {
      final current = [
        legacySession(
          connectionId: 'c1',
          sessionName: 'main',
          connectedAt: DateTime(2025, 2, 1),
          lastAccessedAt: DateTime(2025, 3, 1),
          lastWindowIndex: 1,
          lastPaneId: '%3',
        ),
      ];
      final merged = merger.merge(
        currentSessions: current,
        connectionId: 'c1',
        connectionName: 'Conn-c1',
        host: 'host-c1',
        sessions: [domainSession('main', id: 's0')],
        now: now,
      );
      final s = merged.single;
      expect(s.sessionId, 's0');
      expect(s.connectedAt, DateTime(2025, 2, 1));
      expect(s.lastAccessedAt, DateTime(2025, 3, 1));
      expect(s.lastWindowIndex, 1);
      expect(s.lastPaneId, '%3');
    });

    test(
      'does not adopt when multiple legacy entries share the same label',
      () {
        final current = [
          legacySession(connectionId: 'c1', sessionName: 'tmp'),
          legacySession(connectionId: 'c1', sessionName: 'tmp'),
        ];
        final merged = merger.merge(
          currentSessions: current,
          connectionId: 'c1',
          connectionName: 'Conn-c1',
          host: 'host-c1',
          sessions: [
            domainSession('tmp', id: 'w3'),
            domainSession('tmp', id: 'w4'),
          ],
          now: now,
        );
        expect(merged, hasLength(2));
        // 対応関係が一意に決められないため履歴は引き継がれない（新規扱い）。
        expect(merged.every((s) => s.connectedAt == now), isTrue);
      },
    );

    test('never cross-inherits history when new data has duplicate labels', () {
      // 新データ側に同名ラベルが複数あり、既存の adopting 済みキーが
      // 再利用されないことを確認（重複継承防止）。
      final current = [
        legacySession(
          connectionId: 'c1',
          sessionName: 'tmp',
          connectedAt: DateTime(2025, 2, 1),
        ),
      ];
      final merged = merger.merge(
        currentSessions: current,
        connectionId: 'c1',
        connectionName: 'Conn-c1',
        host: 'host-c1',
        sessions: [
          domainSession('tmp', id: 'w3'),
          domainSession('tmp', id: 'w4'),
        ],
        now: now,
      );
      expect(merged, hasLength(2));
      // tmp（一意）は adopting されて w3 側だけが履歴を持つ。
      expect(merged[0].sessionId, 'w3');
      expect(merged[0].connectedAt, DateTime(2025, 2, 1));
      expect(merged[1].sessionId, 'w4');
      expect(merged[1].connectedAt, now);
    });

    test('drops legacy entry whose label has no match in the new data', () {
      final current = [legacySession(connectionId: 'c1', sessionName: 'stale')];
      final merged = merger.merge(
        currentSessions: current,
        connectionId: 'c1',
        connectionName: 'Conn-c1',
        host: 'host-c1',
        sessions: [domainSession('main', id: 's0')],
        now: now,
      );
      expect(merged.single.sessionName, 'main');
      expect(merged.single.sessionId, 's0');
    });

    test('passes backend kind through to merged sessions', () {
      final merged = merger.merge(
        currentSessions: const [],
        connectionId: 'c1',
        connectionName: 'Conn-c1',
        host: 'host-c1',
        sessions: [domainSession('main', id: 'w1')],
        backend: MultiplexerBackendKind.herdr,
        now: now,
      );
      expect(merged.single.backend, MultiplexerBackendKind.herdr);
    });
  });
}
