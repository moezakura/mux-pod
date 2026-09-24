// P5: ActiveSessionProvider テスト（分割・責務: updateSessionsForConnection の履歴保持・backend デフォルト/herdr 保存）。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/active_session_provider.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_backend.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ActiveSessionProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

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
  });
}
