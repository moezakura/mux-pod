// P5: ActiveSessionProvider テスト（分割・責務: ActiveSession/ActiveSessionsState の JSON round trip・fromJson フォールバック・copyWith）。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ActiveSessionProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
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
  });
}
