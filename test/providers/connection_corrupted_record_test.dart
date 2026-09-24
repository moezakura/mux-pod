// P5: ConnectionProvider テスト（分割・責務: 破損レコード隔離・旧 tmuxPath レコードの移行ロード）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

import 'helpers/connection_test_storage.dart';

void main() {
  group('ConnectionProvider', () {
    setUp(resetConnectionStorage);

    group('corrupted record isolation', () {
      test('keeps healthy records and collects corrupted', () async {
        final storage = SecureStorageService();
        final jsonString = jsonEncode([
          {
            'id': 'c1',
            'name': 'Healthy',
            'host': 'h1',
            'username': 'u1',
            'createdAt': '2025-01-01T00:00:00.000Z',
          },
          {
            'id': 'c2',
            'name': 'Bad multiplexer',
            'host': 'h2',
            'username': 'u2',
            'createdAt': '2025-01-02T00:00:00.000Z',
            'multiplexer': {'backend': 'unknown', 'executablePath': null},
          },
          {
            'name': 'Missing id',
            'host': 'h3',
            'username': 'u3',
            'createdAt': '2025-01-03T00:00:00.000Z',
          },
          'not a map',
        ]);

        await storage.writeValue('connections', jsonString);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(connectionsProvider.notifier).reload();

        final state = container.read(connectionsProvider);
        expect(state.connections, hasLength(1));
        expect(state.connections[0].id, 'c1');
        expect(state.corruptedRecords, hasLength(3));
        expect(state.corruptedRecords[0].id, 'c2');
        expect(state.warning, contains('3'));
      });

      test('old tmuxPath record is migrated and loaded', () async {
        final storage = SecureStorageService();
        final jsonString = jsonEncode([
          {
            'id': 'c1',
            'name': 'Legacy',
            'host': 'h1',
            'username': 'u1',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'tmuxPath': '/custom/tmux',
          },
        ]);

        await storage.writeValue('connections', jsonString);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(connectionsProvider.notifier).reload();

        final state = container.read(connectionsProvider);
        expect(state.connections, hasLength(1));
        expect(state.connections[0].multiplexer.executablePath, '/custom/tmux');
        expect(state.corruptedRecords, isEmpty);
      });
    });
  });
}
