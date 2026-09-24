// P5: ActiveSessionProvider テスト（分割・責務: PROV-ACTIVE 永続化とロード・removeSessionsForConnection の保持）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ActiveSessionProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
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
  });
}
