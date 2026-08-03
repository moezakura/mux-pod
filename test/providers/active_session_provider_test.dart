import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
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
      );
      final json = session.toJson();
      final restored = ActiveSession.fromJson(json);
      expect(restored.key, session.key);
      expect(restored.windowCount, 2);
      expect(restored.lastWindowIndex, 1);
      expect(restored.lastPaneId, '%0');
      expect(restored.isAttached, isTrue);
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
  });
}
