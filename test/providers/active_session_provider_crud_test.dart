// P5: ActiveSessionProvider テスト（分割・責務: セッション CRUD（追加/更新/touch/close/remove/current 選択））。

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
  });
}
