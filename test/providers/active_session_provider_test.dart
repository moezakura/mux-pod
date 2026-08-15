import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ActiveSessionProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(activeSessionsProvider);
      expect(state.sessions, isEmpty);
      expect(state.currentSessionKey, isNull);
      expect(state.currentSession, isNull);
    });

    test('addOrUpdateSession adds a new session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 2,
      );
      final state = container.read(activeSessionsProvider);
      expect(state.sessions, hasLength(1));
      expect(state.sessions[0].key, 'conn-1:main');
      expect(state.sessions[0].sessionId, isNull);
      expect(state.sessions[0].windowCount, 2);
      expect(state.sessions[0].isAttached, isTrue);
    });

    test(
      'addOrUpdateSession with sessionId keys by id (tmux "\$0" / herdr "w3")',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        notifier.addOrUpdateSession(
          connectionId: 'conn-1',
          connectionName: 'My Server',
          host: '192.168.1.1',
          sessionName: 'main',
          sessionId: r'$0',
          windowCount: 2,
        );
        final state = container.read(activeSessionsProvider);
        expect(state.sessions, hasLength(1));
        expect(state.sessions[0].key, r'conn-1:$0');
        expect(state.sessions[0].sessionId, r'$0');
        expect(state.sessions[0].sessionName, 'main');
      },
    );

    test('same sessionName with different sessionId stays separate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        sessionId: 'w3',
        windowCount: 1,
        lastPaneId: '%3',
      );
      notifier.addOrUpdateSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        sessionId: 'w4',
        windowCount: 2,
        lastPaneId: '%4',
      );

      var state = container.read(activeSessionsProvider);
      expect(state.sessions, hasLength(2));
      expect(state.sessions.map((s) => s.key), ['c1:w3', 'c1:w4']);

      final w4Before = state.sessions
          .singleWhere((s) => s.sessionId == 'w4')
          .lastAccessedAt;

      // touchSession は ID 指定のものだけを更新する（同名混線しない）
      notifier.touchSession('c1', 'tmp', sessionId: 'w3');
      state = container.read(activeSessionsProvider);
      final w3 = state.sessions.singleWhere((s) => s.sessionId == 'w3');
      final w4 = state.sessions.singleWhere((s) => s.sessionId == 'w4');
      expect(w3.lastAccessedAt, isNotNull);
      expect(w4.lastAccessedAt, w4Before);

      // closeSession は ID 指定のものだけを削除する
      notifier.closeSession('c1', 'tmp', sessionId: 'w3');
      state = container.read(activeSessionsProvider);
      expect(state.sessions.map((s) => s.key), ['c1:w4']);
    });

    test(
      'updateWindowCount with sessionId targets only the id-keyed session',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        notifier.addOrUpdateSession(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessionName: 'tmp',
          sessionId: 'w3',
          windowCount: 1,
        );
        notifier.addOrUpdateSession(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessionName: 'tmp',
          sessionId: 'w4',
          windowCount: 2,
        );

        notifier.updateWindowCount('c1', 'tmp', 9, sessionId: 'w3');

        final sessions = container.read(activeSessionsProvider).sessions;
        expect(sessions.singleWhere((s) => s.sessionId == 'w3').windowCount, 9);
        expect(sessions.singleWhere((s) => s.sessionId == 'w4').windowCount, 2);
      },
    );

    test('addOrUpdateSession updates existing session keeping last pane', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 2,
        lastPaneId: '%0',
      );
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 3,
      );
      final state = container.read(activeSessionsProvider);
      expect(state.sessions[0].windowCount, 3);
      expect(state.sessions[0].lastPaneId, '%0');
    });

    test('updateLastPane writes last pane id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 2,
      );
      notifier.updateLastPane(
        connectionId: 'conn-1',
        sessionName: 'main',
        windowIndex: 1,
        paneId: '%5',
      );
      final state = container.read(activeSessionsProvider);
      expect(state.sessions[0].lastWindowIndex, 1);
      expect(state.sessions[0].lastPaneId, '%5');
    });

    test('setCurrentSession and currentSession', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 2,
      );
      notifier.setCurrentSession('conn-1', 'main');
      final state = container.read(activeSessionsProvider);
      expect(state.currentSessionKey, 'conn-1:main');
      expect(state.currentSession?.sessionName, 'main');
    });

    test('setCurrentSession with sessionId matches the id-keyed session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        sessionId: 'w3',
        windowCount: 1,
      );
      notifier.addOrUpdateSession(
        connectionId: 'c1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'tmp',
        sessionId: 'w4',
        windowCount: 1,
      );

      notifier.setCurrentSession('c1', 'tmp', sessionId: 'w4');

      final state = container.read(activeSessionsProvider);
      expect(state.currentSessionKey, 'c1:w4');
      expect(state.currentSession?.sessionId, 'w4');
      expect(state.currentSession?.sessionName, 'tmp');
    });

    test('clearCurrentSession', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 2,
      );
      notifier.setCurrentSession('conn-1', 'main');
      notifier.clearCurrentSession();
      expect(container.read(activeSessionsProvider).currentSession, isNull);
    });

    test('closeSession removes session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 2,
      );
      notifier.closeSession('conn-1', 'main');
      expect(container.read(activeSessionsProvider).sessions, isEmpty);
    });

    test(
      'PROV-ACTIVE-028 updateWindowCount changes only the target and persists it',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        notifier.addOrUpdateSession(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessionName: 'main',
          windowCount: 2,
          lastWindowIndex: 1,
          lastPaneId: '%3',
        );
        notifier.addOrUpdateSession(
          connectionId: 'c2',
          connectionName: 'B',
          host: 'b',
          sessionName: 'other',
          windowCount: 4,
        );
        final before = container.read(activeSessionsProvider);
        final targetBefore = before.sessions.first;
        final otherBefore = before.sessions.last;

        notifier.updateWindowCount('c1', 'main', 7);

        final sessions = container.read(activeSessionsProvider).sessions;
        final target = sessions.singleWhere(
          (session) => session.key == 'c1:main',
        );
        final other = sessions.singleWhere(
          (session) => session.key == 'c2:other',
        );
        expect(target.windowCount, 7);
        expect(target.connectedAt, targetBefore.connectedAt);
        expect(target.lastWindowIndex, 1);
        expect(target.lastPaneId, '%3');
        expect(identical(other, otherBefore), isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 10));
        final prefs = await SharedPreferences.getInstance();
        final persisted =
            jsonDecode(prefs.getString('active_sessions')!) as List<dynamic>;
        final targetJson = persisted.cast<Map<String, dynamic>>().singleWhere(
          (session) => session['connectionId'] == 'c1',
        );
        final otherJson = persisted.cast<Map<String, dynamic>>().singleWhere(
          (session) => session['connectionId'] == 'c2',
        );
        expect(targetJson['windowCount'], 7);
        expect(otherJson['windowCount'], 4);
      },
    );

    test(
      'PROV-ACTIVE-029 touchSession advances only target timestamp and persists it',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        notifier.addOrUpdateSession(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessionName: 'main',
          windowCount: 2,
        );
        notifier.addOrUpdateSession(
          connectionId: 'c2',
          connectionName: 'B',
          host: 'b',
          sessionName: 'other',
          windowCount: 4,
        );
        final before = container.read(activeSessionsProvider).sessions;
        final targetBefore = before.first;
        final otherBefore = before.last;
        await Future<void>.delayed(const Duration(milliseconds: 1));

        notifier.touchSession('c1', 'main');

        final sessions = container.read(activeSessionsProvider).sessions;
        final target = sessions.singleWhere(
          (session) => session.key == 'c1:main',
        );
        final other = sessions.singleWhere(
          (session) => session.key == 'c2:other',
        );
        expect(target.lastAccessedAt, isNotNull);
        expect(
          target.lastAccessedAt!.isAfter(targetBefore.lastAccessedAt!),
          isTrue,
        );
        expect(target.windowCount, 2);
        expect(target.connectedAt, targetBefore.connectedAt);
        expect(identical(other, otherBefore), isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 10));
        final prefs = await SharedPreferences.getInstance();
        final persisted =
            jsonDecode(prefs.getString('active_sessions')!) as List<dynamic>;
        final targetJson = persisted.cast<Map<String, dynamic>>().singleWhere(
          (session) => session['connectionId'] == 'c1',
        );
        final otherJson = persisted.cast<Map<String, dynamic>>().singleWhere(
          (session) => session['connectionId'] == 'c2',
        );
        expect(
          targetJson['lastAccessedAt'],
          target.lastAccessedAt!.toIso8601String(),
        );
        expect(
          otherJson['lastAccessedAt'],
          otherBefore.lastAccessedAt!.toIso8601String(),
        );
      },
    );

    test(
      'PROV-ACTIVE-034 removeSession removes only the exact session and persists aliases behavior',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        for (final session in [
          ('c1', 'main'),
          ('c1', 'other'),
          ('c2', 'main'),
        ]) {
          notifier.addOrUpdateSession(
            connectionId: session.$1,
            connectionName: session.$1,
            host: '${session.$1}.example',
            sessionName: session.$2,
            windowCount: 1,
          );
        }
        notifier.setCurrentSession('c1', 'main');

        notifier.removeSession('c1', 'main');

        final state = container.read(activeSessionsProvider);
        expect(state.sessions.map((session) => session.key), [
          'c1:other',
          'c2:main',
        ]);
        expect(state.currentSessionKey, 'c1:main');
        expect(state.currentSession, isNull);

        await Future<void>.delayed(const Duration(milliseconds: 10));
        final prefs = await SharedPreferences.getInstance();
        final persisted =
            jsonDecode(prefs.getString('active_sessions')!) as List<dynamic>;
        expect(
          persisted.map(
            (session) =>
                '${session['connectionId'] as String}:${session['sessionName'] as String}',
          ),
          ['c1:other', 'c2:main'],
        );
      },
    );

    test('clear resets sessions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'My Server',
        host: '192.168.1.1',
        sessionName: 'main',
        windowCount: 2,
      );
      notifier.clear();
      expect(container.read(activeSessionsProvider).sessions, isEmpty);
    });

    test('getSessionsForConnection filters by connection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeSessionsProvider.notifier);
      notifier.addOrUpdateSession(
        connectionId: 'conn-1',
        connectionName: 'A',
        host: 'a',
        sessionName: 'main',
        windowCount: 1,
      );
      notifier.addOrUpdateSession(
        connectionId: 'conn-2',
        connectionName: 'B',
        host: 'b',
        sessionName: 'main',
        windowCount: 1,
      );
      final state = container.read(activeSessionsProvider);
      expect(state.getSessionsForConnection('conn-1'), hasLength(1));
    });

    test('ActiveSession JSON round trip', () {
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      final session = ActiveSession(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowCount: 2,
        connectedAt: now,
        lastWindowIndex: 1,
        lastPaneId: '%0',
        lastAccessedAt: now.add(const Duration(minutes: 1)),
      );
      final json = session.toJson();
      final restored = ActiveSession.fromJson(json);
      expect(restored.key, session.key);
      expect(restored.windowCount, 2);
      expect(restored.lastWindowIndex, 1);
      expect(restored.lastPaneId, '%0');
      expect(restored.isAttached, isTrue);
      expect(restored.connectionId, 'c1');
      expect(restored.connectionName, 'Server');
      expect(restored.host, 'h');
      expect(restored.sessionName, 'main');
      expect(restored.sessionId, isNull);
      expect(restored.connectedAt, now);
      expect(restored.lastAccessedAt, now.add(const Duration(minutes: 1)));
    });

    test('ActiveSession JSON round trip preserves sessionId', () {
      final session = ActiveSession(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'tmp',
        sessionId: 'w3',
        windowCount: 1,
        connectedAt: DateTime(2025, 1, 1),
        backend: MultiplexerBackendKind.herdr,
      );
      final json = session.toJson();
      expect(json['sessionId'], 'w3');

      final restored = ActiveSession.fromJson(json);
      expect(restored.sessionId, 'w3');
      expect(restored.key, 'c1:w3');
      expect(restored.key, session.key);
    });

    test(
      'ActiveSession.fromJson without sessionId falls back to null (legacy)',
      () {
        final json = ActiveSession(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'h',
          sessionName: 'main',
          windowCount: 1,
          connectedAt: DateTime(2025, 1, 1),
        ).toJson()..remove('sessionId');

        final restored = ActiveSession.fromJson(json);
        expect(restored.sessionId, isNull);
        expect(restored.key, 'c1:main');
      },
    );

    test('ActiveSession copyWith with clearLastPane', () {
      final now = DateTime(2025, 1, 1);
      final session = ActiveSession(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowCount: 2,
        connectedAt: now,
        isAttached: true,
        lastPaneId: '%0',
      );
      final cleared = session.copyWith(clearLastPane: true);
      expect(cleared.lastPaneId, isNull);
    });

    test('ActiveSessionsState copyWith clearCurrentSession', () {
      const state = ActiveSessionsState(currentSessionKey: 'a:b');
      final cleared = state.copyWith(clearCurrentSession: true);
      expect(cleared.currentSessionKey, isNull);
    });

    test(
      'loads persisted sessions and exposes currentSession null for stale key',
      () async {
        final persisted = ActiveSession(
          connectionId: 'saved',
          connectionName: 'Saved Server',
          host: 'saved.example',
          sessionName: 'work',
          windowCount: 4,
          connectedAt: DateTime(2025, 1, 1),
          isAttached: false,
        );
        SharedPreferences.setMockInitialValues({
          'active_sessions': '[${jsonEncode(persisted.toJson())}]',
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(activeSessionsProvider);
        await Future<void>.delayed(Duration.zero);

        final loaded = container.read(activeSessionsProvider).sessions.single;
        expect(loaded.connectionId, 'saved');
        expect(loaded.isAttached, isFalse);

        const stale = ActiveSessionsState(
          sessions: [],
          currentSessionKey: 'missing:session',
        );
        expect(stale.currentSession, isNull);
      },
    );

    test(
      'persists updates and removeSessionsForConnection preserves others',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(activeSessionsProvider.notifier);
        notifier.addOrUpdateSession(
          connectionId: 'c1',
          connectionName: 'A',
          host: 'a',
          sessionName: 'main',
          windowCount: 1,
        );
        notifier.addOrUpdateSession(
          connectionId: 'c2',
          connectionName: 'B',
          host: 'b',
          sessionName: 'other',
          windowCount: 2,
        );

        notifier.removeSessionsForConnection('c1');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          container.read(activeSessionsProvider).sessions.single.connectionId,
          'c2',
        );
        final prefs = await SharedPreferences.getInstance();
        final records =
            jsonDecode(prefs.getString('active_sessions')!) as List<dynamic>;
        expect(records, hasLength(1));
        expect(records.single['connectionId'], 'c2');
      },
    );

    test('updateSessionsForConnection preserves history fields', () {
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

      notifier.updateSessionsForConnection(
        connectionId: 'c1',
        connectionName: 'Renamed',
        host: 'new-host',
        tmuxSessions: [
          const TmuxSession(name: 'main', windowCount: 3, attached: false),
        ],
      );

      final updated = container.read(activeSessionsProvider).sessions.single;
      expect(updated.connectionName, 'Renamed');
      expect(updated.host, 'new-host');
      expect(updated.windowCount, 3);
      expect(updated.isAttached, isFalse);
      expect(updated.connectedAt, before.connectedAt);
      expect(updated.lastWindowIndex, 2);
      expect(updated.lastPaneId, '%9');
      expect(updated.backend, MultiplexerBackendKind.tmux);
    });

    test('ActiveSession defaults backend to tmux', () {
      final session = ActiveSession(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowCount: 1,
        connectedAt: DateTime(2025, 1, 1),
      );
      expect(session.backend, MultiplexerBackendKind.tmux);
    });

    test('ActiveSession JSON round trip preserves herdr backend', () {
      final session = ActiveSession(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowCount: 1,
        connectedAt: DateTime(2025, 1, 1),
        backend: MultiplexerBackendKind.herdr,
      );
      final json = session.toJson();
      expect(json['backend'], 'herdr');

      final restored = ActiveSession.fromJson(json);
      expect(restored.backend, MultiplexerBackendKind.herdr);
      expect(restored.key, session.key);
    });

    test(
      'ActiveSession.fromJson falls back to tmux when backend is missing',
      () {
        final json = ActiveSession(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'h',
          sessionName: 'main',
          windowCount: 1,
          connectedAt: DateTime(2025, 1, 1),
        ).toJson()..remove('backend');

        final restored = ActiveSession.fromJson(json);
        expect(restored.backend, MultiplexerBackendKind.tmux);
      },
    );

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
