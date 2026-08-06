import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
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
      expect(state.sessions[0].windowCount, 2);
      expect(state.sessions[0].isAttached, isTrue);
    });

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
      expect(restored.connectedAt, now);
      expect(restored.lastAccessedAt, now.add(const Duration(minutes: 1)));
    });

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
    });
  });
}
