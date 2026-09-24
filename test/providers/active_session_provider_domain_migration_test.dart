// P5: ActiveSessionProvider テスト（分割・責務: updateSessionsFromDomain の同名 ID 分離・legacy 移行・曖昧非移行・不一致破棄）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ActiveSessionProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'updateSessionsFromDomain registers domain sessions with backend and preserves history',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        notifier.addOrUpdateSession(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessionName: 'main',
          windowCount: 1,
          lastWindowIndex: 2,
          lastPaneId: '%9',
        );
        final before = container.read(activeSessionsProvider).sessions.single;

        notifier.updateSessionsFromDomain(
          connectionId: 'c1',
          connectionName: 'Renamed',
          host: 'new-host',
          sessions: const [
            MultiplexerSession(name: 'main', windowCount: 3, attached: false),
            MultiplexerSession(
              name: 'herdr-ws',
              windowCount: 5,
              attached: true,
            ),
          ],
          backend: MultiplexerBackendKind.herdr,
        );

        final sessions = container.read(activeSessionsProvider).sessions;
        expect(sessions, hasLength(2));

        final main = sessions.singleWhere((s) => s.sessionName == 'main');
        expect(main.connectionName, 'Renamed');
        expect(main.host, 'new-host');
        expect(main.windowCount, 3);
        expect(main.isAttached, isFalse);
        expect(main.backend, MultiplexerBackendKind.herdr);
        expect(main.connectedAt, before.connectedAt);
        expect(main.lastWindowIndex, 2);
        expect(main.lastPaneId, '%9');

        final ws = sessions.singleWhere((s) => s.sessionName == 'herdr-ws');
        expect(ws.windowCount, 5);
        expect(ws.isAttached, isTrue);
        expect(ws.backend, MultiplexerBackendKind.herdr);
      },
    );

    test('updateSessionsFromDomain preserves other connections', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'c2',
        connectionName: 'B',
        host: 'b',
        sessionName: 'other',
        windowCount: 4,
      );

      notifier.updateSessionsFromDomain(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessions: const [MultiplexerSession(name: 'main', windowCount: 1)],
        backend: MultiplexerBackendKind.herdr,
      );

      final sessions = container.read(activeSessionsProvider).sessions;
      expect(sessions.map((s) => s.connectionId), ['c2', 'c1']);
      expect(sessions.last.backend, MultiplexerBackendKind.herdr);
    });

    test('updateSessionsFromDomain keeps same-label sessions separated by id '
        'and never cross-inherits history', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);

      // 前回登録: 同名ラベル "tmp" の w3 / w4（w3 にのみ履歴あり）
      notifier.updateSessionsFromDomain(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessions: const [
          MultiplexerSession(
            name: 'tmp',
            id: 'w3',
            windowCount: 1,
            attached: true,
          ),
          MultiplexerSession(name: 'tmp', id: 'w4', windowCount: 2),
        ],
        backend: MultiplexerBackendKind.herdr,
      );
      notifier.addOrUpdateSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        sessionId: 'w3',
        windowCount: 1,
        lastWindowIndex: 5,
        lastPaneId: '%5',
      );
      final before = container.read(activeSessionsProvider).sessions;

      // 再取得: 同じ2ワークスペースが来ても、w4 が w3 の履歴を横継承しない
      notifier.updateSessionsFromDomain(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessions: const [
          MultiplexerSession(
            name: 'tmp',
            id: 'w3',
            windowCount: 3,
            attached: true,
          ),
          MultiplexerSession(name: 'tmp', id: 'w4', windowCount: 4),
        ],
        backend: MultiplexerBackendKind.herdr,
      );

      final sessions = container.read(activeSessionsProvider).sessions;
      expect(sessions.map((s) => s.key), ['c1:w3', 'c1:w4']);

      final w3 = sessions.singleWhere((s) => s.sessionId == 'w3');
      final w4 = sessions.singleWhere((s) => s.sessionId == 'w4');
      // w3: 自セッションの履歴を保持
      expect(w3.windowCount, 3);
      expect(w3.connectedAt, before.first.connectedAt);
      expect(w3.lastWindowIndex, 5);
      expect(w3.lastPaneId, '%5');
      // w4: 同名だが w3 の履歴は横継承しない
      expect(w4.windowCount, 4);
      expect(w4.lastWindowIndex, isNull);
      expect(w4.lastPaneId, isNull);
    });

    test('updateSessionsFromDomain migrates legacy sessionId-null entry to the '
        'id key preserving history (herdr tmp w3/w4 pattern)', () async {
      // 旧データ（sessionId 導入前）: herdr workspace "tmp" が
      // sessionId: null のまま保存されている（Dashboard からは c1:tmp で
      // 表示・タップされていた）。
      final legacy = ActiveSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        windowCount: 1,
        connectedAt: DateTime(2025, 1, 1, 9, 0, 0),
        lastAccessedAt: DateTime(2025, 1, 5, 18, 30, 0),
        lastWindowIndex: 3,
        lastPaneId: '%3',
      );
      SharedPreferences.setMockInitialValues({
        'active_sessions': '[${jsonEncode(legacy.toJson())}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeSessionsProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(activeSessionsProvider).sessions.single.key,
        'c1:tmp',
      );

      // 接続/ホーム画面のリロードで新データ（sessionId 付き）が届く。
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.updateSessionsFromDomain(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessions: const [
          MultiplexerSession(
            name: 'tmp',
            id: 'w3',
            windowCount: 2,
            attached: true,
          ),
          MultiplexerSession(name: 'tmp', id: 'w4', windowCount: 1),
        ],
        backend: MultiplexerBackendKind.herdr,
      );

      final sessions = container.read(activeSessionsProvider).sessions;
      // 旧 c1:tmp は消滅し、ID キーの 2 エントリになる（Dashboard の
      // 同名 tmp 2 件・キー衝突が解消される）。
      expect(sessions.map((s) => s.key), ['c1:w3', 'c1:w4']);

      final w3 = sessions.singleWhere((s) => s.sessionId == 'w3');
      // 旧エントリ（sessionId: null）の履歴が w3 に引き継がれる。
      expect(w3.sessionName, 'tmp');
      expect(w3.connectedAt, legacy.connectedAt);
      expect(w3.lastAccessedAt, legacy.lastAccessedAt);
      expect(w3.lastWindowIndex, 3);
      expect(w3.lastPaneId, '%3');
      expect(w3.backend, MultiplexerBackendKind.herdr);
      expect(w3.windowCount, 2);

      // w4: 同名だが別ワークスペースなので履歴は引き継がない。
      final w4 = sessions.singleWhere((s) => s.sessionId == 'w4');
      expect(w4.connectedAt.isAfter(legacy.connectedAt), isTrue);
      expect(w4.lastWindowIndex, isNull);
      expect(w4.lastPaneId, isNull);

      // 永続化: ストレージ上も ID キーで sessionId 付きで保存される。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(prefs.getString('active_sessions')!) as List<dynamic>;
      final records = persisted.cast<Map<String, dynamic>>();
      expect(records, hasLength(2));
      expect(records.map((s) => s['sessionId']), ['w3', 'w4']);
      final w3Json = records.singleWhere((s) => s['sessionId'] == 'w3');
      expect(w3Json['connectedAt'], legacy.connectedAt.toIso8601String());
      expect(
        w3Json['lastAccessedAt'],
        legacy.lastAccessedAt!.toIso8601String(),
      );
      expect(w3Json['backend'], 'herdr');
    });

    test('updateSessionsFromDomain does not migrate when multiple legacy entries '
        'share the same label (ambiguous correspondence)', () async {
      // 旧データ: 同名 "tmp" が sessionId: null で 2 件（w3/w4 相当）。
      // 両方 c1:tmp キーで衝突しており、対応関係を一意に決められない。
      final legacyW3 = ActiveSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        windowCount: 1,
        connectedAt: DateTime(2025, 1, 1),
        lastAccessedAt: DateTime(2025, 1, 2),
      );
      final legacyW4 = ActiveSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        windowCount: 1,
        connectedAt: DateTime(2025, 1, 3),
        lastAccessedAt: DateTime(2025, 1, 4),
      );
      SharedPreferences.setMockInitialValues({
        'active_sessions':
            '[${jsonEncode(legacyW3.toJson())},${jsonEncode(legacyW4.toJson())}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeSessionsProvider);
      await Future<void>.delayed(Duration.zero);
      final loaded = container.read(activeSessionsProvider).sessions;
      expect(loaded, hasLength(2));
      expect(loaded.map((s) => s.key), ['c1:tmp', 'c1:tmp']);

      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.updateSessionsFromDomain(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessions: const [
          MultiplexerSession(name: 'tmp', id: 'w3', windowCount: 2),
          MultiplexerSession(name: 'tmp', id: 'w4', windowCount: 2),
        ],
        backend: MultiplexerBackendKind.herdr,
      );

      // 旧エントリは破棄され、ID キーの 2 エントリに置き換わる。
      // 曖昧なため履歴は引き継がない（connectedAt は新規日時）。
      final sessions = container.read(activeSessionsProvider).sessions;
      expect(sessions.map((s) => s.key), ['c1:w3', 'c1:w4']);
      for (final s in sessions) {
        expect(s.connectedAt.isAfter(legacyW4.connectedAt), isTrue);
        expect(s.lastWindowIndex, isNull);
        expect(s.lastPaneId, isNull);
      }
    });

    test(
      'updateSessionsFromDomain drops legacy entries whose label has no match '
      'in the new data',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        // 旧エントリ（sessionId: null）
        notifier.addOrUpdateSession(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessionName: 'old-session',
          windowCount: 1,
          lastWindowIndex: 2,
          lastPaneId: '%2',
        );

        // 新データには "old-session" が無い（workspace が消えた）
        notifier.updateSessionsFromDomain(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessions: const [
            MultiplexerSession(name: 'main', id: r'$0', windowCount: 3),
          ],
        );

        final sessions = container.read(activeSessionsProvider).sessions;
        expect(sessions.map((s) => s.key), [r'c1:$0']);
        expect(sessions.single.sessionName, 'main');
        expect(sessions.single.sessionId, r'$0');
      },
    );
  });
}
