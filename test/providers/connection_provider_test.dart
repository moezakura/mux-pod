import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/connection/connection_migration.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ConnectionProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SecureStorageService.setTestValues({});
    });

    test('initial state is loading with empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(connectionsProvider);
      expect(state.isLoading, isTrue);
      expect(state.connections, isEmpty);
      expect(state.corruptedRecords, isEmpty);
      expect(state.error, isNull);
      expect(state.warning, isNull);
    });

    test('add updates state and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future.delayed(Duration.zero);

      final connection = Connection(
        id: 'conn-1',
        name: 'My Server',
        host: '192.168.1.1',
        username: 'user',
        createdAt: DateTime(2025, 1, 1),
      );

      await container.read(connectionsProvider.notifier).add(connection);

      final state = container.read(connectionsProvider);
      expect(state.connections, hasLength(1));
      expect(state.connections[0].name, 'My Server');
      expect(state.connections[0].port, 22);
      expect(state.connections[0].authMethod, 'password');
      expect(state.connections[0].multiplexer.backend, BackendType.tmux);
      expect(state.connections[0].multiplexer.executablePath, isNull);

      final secure = SecureStorageService();
      expect(await secure.readValue('connections'), isNotNull);
    });

    test('remove deletes connection', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future.delayed(Duration.zero);

      final connection = Connection(
        id: 'conn-1',
        name: 'My Server',
        host: '192.168.1.1',
        username: 'user',
        createdAt: DateTime(2025, 1, 1),
      );

      await container.read(connectionsProvider.notifier).add(connection);
      await container.read(connectionsProvider.notifier).remove('conn-1');

      expect(container.read(connectionsProvider).connections, isEmpty);
    });

    test('update replaces connection', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future.delayed(Duration.zero);

      final connection = Connection(
        id: 'conn-1',
        name: 'My Server',
        host: '192.168.1.1',
        username: 'user',
        createdAt: DateTime(2025, 1, 1),
      );

      await container.read(connectionsProvider.notifier).add(connection);

      final updated = connection.copyWith(name: 'Renamed');
      await container.read(connectionsProvider.notifier).update(updated);

      expect(container.read(connectionsProvider).connections[0].name, 'Renamed');
    });

    test('findByDeepLinkIdOrName', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future.delayed(Duration.zero);

      final connection = Connection(
        id: 'conn-1',
        name: 'My Server',
        host: '192.168.1.1',
        username: 'user',
        deepLinkId: 'server-a',
        createdAt: DateTime(2025, 1, 1),
      );

      await container.read(connectionsProvider.notifier).add(connection);

      final notifier = container.read(connectionsProvider.notifier);
      expect(notifier.findByDeepLinkIdOrName('server-a')?.id, 'conn-1');
      expect(notifier.findByDeepLinkIdOrName('My Server')?.id, 'conn-1');
      expect(notifier.findByDeepLinkIdOrName('my server')?.id, 'conn-1');
      expect(notifier.findByDeepLinkIdOrName('missing'), isNull);
    });

    test('filteredConnectionsProvider filters by search', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future.delayed(Duration.zero);

      await container.read(connectionsProvider.notifier).add(
        Connection(
          id: 'c1',
          name: 'Alpha',
          host: '10.0.0.1',
          username: 'user',
          createdAt: DateTime(2025, 1, 1),
        ),
      );
      await container.read(connectionsProvider.notifier).add(
        Connection(
          id: 'c2',
          name: 'Beta',
          host: '10.0.0.2',
          username: 'admin',
          createdAt: DateTime(2025, 1, 1),
        ),
      );

      container.read(connectionSearchProvider.notifier).setQuery('beta');

      final filtered = container.read(filteredConnectionsProvider);
      expect(filtered, hasLength(1));
      expect(filtered[0].name, 'Beta');
    });

    test('selectedConnectionProvider returns selected connection', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future.delayed(Duration.zero);

      final connection = Connection(
        id: 'conn-1',
        name: 'My Server',
        host: '192.168.1.1',
        username: 'user',
        createdAt: DateTime(2025, 1, 1),
      );

      await container.read(connectionsProvider.notifier).add(connection);
      container.read(selectedConnectionIdProvider.notifier).select('conn-1');

      expect(container.read(selectedConnectionProvider)?.id, 'conn-1');
    });

    group('Connection', () {
      test('JSON round trip with defaults', () {
        final now = DateTime(2025, 1, 1);
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          createdAt: now,
          lastConnectedAt: now,
          deepLinkId: 'd1',
        );

        final json = connection.toJson();
        final restored = Connection.fromJson(json);

        expect(restored.id, 'c1');
        expect(restored.port, 22);
        expect(restored.authMethod, 'password');
        expect(restored.deepLinkId, 'd1');
        expect(restored.lastConnectedAt, isNotNull);
        expect(restored.multiplexer, const MultiplexerConfig.tmux());
        expect(json['multiplexer'], isA<Map<String, dynamic>>());
        expect(json['multiplexer']['backend'], 'tmux');
        expect(json['multiplexer']['executablePath'], isNull);
        expect(json, isNot(contains('tmuxPath')));
      });

      test('JSON round trip with custom multiplexer', () {
        final now = DateTime(2025, 1, 1);
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          multiplexer: const MultiplexerConfig.tmux('/usr/local/bin/tmux'),
          createdAt: now,
        );

        final json = connection.toJson();
        final restored = Connection.fromJson(json);

        expect(restored.multiplexer.backend, BackendType.tmux);
        expect(restored.multiplexer.executablePath, '/usr/local/bin/tmux');
        expect(json['multiplexer']['executablePath'], '/usr/local/bin/tmux');
      });

      test('fromJson fills missing fields with tmux defaults', () {
        final json = <String, dynamic>{
          'id': 'c1',
          'name': 'Server',
          'host': 'h',
          'username': 'u',
          'createdAt': '2025-01-01T00:00:00.000Z',
        };

        final restored = Connection.fromJson(json);
        expect(restored.port, 22);
        expect(restored.authMethod, 'password');
        expect(restored.deepLinkId, isNull);
        expect(restored.lastConnectedAt, isNull);
        expect(restored.multiplexer, const MultiplexerConfig.tmux());
      });

      test('fromJson with old tmuxPath maps to multiplexer', () {
        final json = <String, dynamic>{
          'id': 'c1',
          'name': 'Server',
          'host': 'h',
          'username': 'u',
          'createdAt': '2025-01-01T00:00:00.000Z',
          'tmuxPath': '/custom/tmux',
        };

        final restored = Connection.fromJson(json);
        expect(restored.multiplexer.backend, BackendType.tmux);
        expect(restored.multiplexer.executablePath, '/custom/tmux');
      });

      test('fromJson empty tmuxPath becomes null executablePath', () {
        final json = <String, dynamic>{
          'id': 'c1',
          'name': 'Server',
          'host': 'h',
          'username': 'u',
          'createdAt': '2025-01-01T00:00:00.000Z',
          'tmuxPath': '',
        };

        final restored = Connection.fromJson(json);
        expect(restored.multiplexer.executablePath, isNull);
      });

      test('fromJson multiplexer wins over tmuxPath', () {
        final json = <String, dynamic>{
          'id': 'c1',
          'name': 'Server',
          'host': 'h',
          'username': 'u',
          'createdAt': '2025-01-01T00:00:00.000Z',
          'tmuxPath': '/from/legacy',
          'multiplexer': {
            'backend': 'tmux',
            'executablePath': '/from/multiplexer',
          },
        };

        final restored = Connection.fromJson(json);
        expect(restored.multiplexer.executablePath, '/from/multiplexer');
      });

      test('fromJson unknown backend is a per-record error', () {
        final json = <String, dynamic>{
          'id': 'c1',
          'name': 'Server',
          'host': 'h',
          'username': 'u',
          'createdAt': '2025-01-01T00:00:00.000Z',
          'multiplexer': {
            'backend': 'unknown',
            'executablePath': null,
          },
        };

        expect(() => Connection.fromJson(json), throwsFormatException);
      });

      test('copyWith multiplexer replaces whole object and clears executablePath', () {
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          multiplexer: const MultiplexerConfig.tmux('/old'),
          createdAt: DateTime(2025, 1, 1),
        );

        final cleared = connection.copyWith(
          multiplexer: const MultiplexerConfig.tmux(),
        );
        expect(cleared.multiplexer.executablePath, isNull);
      });

      test('copyWith legacy tmuxPath maps to multiplexer', () {
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          createdAt: DateTime(2025, 1, 1),
        );

        // ignore: deprecated_member_use_from_same_package
        final updated = connection.copyWith(tmuxPath: '/legacy');
        expect(updated.multiplexer.executablePath, '/legacy');
      });

      test('copyWith multiplexer wins over tmuxPath', () {
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          createdAt: DateTime(2025, 1, 1),
        );

        final updated = connection.copyWith(
          multiplexer: const MultiplexerConfig.tmux('/multiplexer'),
          // ignore: deprecated_member_use_from_same_package
          tmuxPath: '/legacy',
        );
        expect(updated.multiplexer.executablePath, '/multiplexer');
      });

      test('legacy tmuxPath getter maps to multiplexer.executablePath', () {
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          multiplexer: const MultiplexerConfig.tmux('/tmux'),
          createdAt: DateTime(2025, 1, 1),
        );

        // ignore: deprecated_member_use, deprecated_member_use_from_same_package
        expect(connection.tmuxPath, '/tmux');
      });

      test('copyWith clearDeepLinkId', () {
        final now = DateTime(2025, 1, 1);
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          createdAt: now,
          deepLinkId: 'd1',
        );

        final cleared = connection.copyWith(clearDeepLinkId: true);
        expect(cleared.deepLinkId, isNull);
      });
    });

    test('sort by lastConnected then created', () {
      final c1 = Connection(
        id: 'c1',
        name: 'Alpha',
        host: 'h1',
        username: 'u',
        createdAt: DateTime(2025, 1, 2),
      );
      final c2 = Connection(
        id: 'c2',
        name: 'Beta',
        host: 'h2',
        username: 'u',
        createdAt: DateTime(2025, 1, 1),
        lastConnectedAt: DateTime(2025, 1, 3),
      );

      final list = [c1, c2];
      list.sort((a, b) {
        final aTime = a.lastConnectedAt ?? a.createdAt;
        final bTime = b.lastConnectedAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      expect(list[0].id, 'c2');
      expect(list[1].id, 'c1');
    });

    group('ConnectionMigration', () {
      test('migrate with old tmuxPath records', () async {
        final secure = SecureStorageService();
        final oldJson = jsonEncode([
          {
            'id': 'c1',
            'name': 'Server',
            'host': 'h',
            'username': 'u',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'tmuxPath': '/usr/bin/tmux',
          },
          {
            'id': 'c2',
            'name': 'Server2',
            'host': 'h2',
            'username': 'u2',
            'createdAt': '2025-01-02T00:00:00.000Z',
            'tmuxPath': '',
          },
        ]);

        final result = await ConnectionMigration.migrate(
          secure: secure,
          sourceJson: oldJson,
        );

        expect(result.error, isNull);
        final migratedList = jsonDecode(result.json!) as List<dynamic>;
        expect(migratedList, hasLength(2));
        expect(migratedList[0]['tmuxPath'], isNull);
        expect(migratedList[0]['multiplexer']['backend'], 'tmux');
        expect(migratedList[0]['multiplexer']['executablePath'], '/usr/bin/tmux');
        expect(migratedList[1]['multiplexer']['executablePath'], isNull);

        // backup should be deleted on success
        expect(await secure.readValue('connections_backup_v2'), isNull);
        // primary should contain migrated data
        expect(await secure.readValue('connections'), result.json);
      });

      test('migrate with mixed old/new json, multiplexer wins', () async {
        final secure = SecureStorageService();
        final oldJson = jsonEncode([
          {
            'id': 'c1',
            'name': 'Server',
            'host': 'h',
            'username': 'u',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'tmuxPath': '/legacy',
            'multiplexer': {
              'backend': 'tmux',
              'executablePath': '/winner',
            },
          },
        ]);

        final result = await ConnectionMigration.migrate(
          secure: secure,
          sourceJson: oldJson,
        );

        expect(result.error, isNull);
        final migratedList = jsonDecode(result.json!) as List<dynamic>;
        expect(migratedList[0]['multiplexer']['executablePath'], '/winner');
        expect(migratedList[0], isNot(contains('tmuxPath')));
      });

      test('migrate leaves already-migrated data untouched', () async {
        final secure = SecureStorageService();
        final newJson = jsonEncode([
          {
            'id': 'c1',
            'name': 'Server',
            'host': 'h',
            'username': 'u',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'multiplexer': {
              'backend': 'tmux',
              'executablePath': '/tmux',
            },
          },
        ]);

        final result = await ConnectionMigration.migrate(
          secure: secure,
          sourceJson: newJson,
        );

        expect(result.json, newJson);
        expect(await secure.readValue('connections_backup_v2'), isNull);
      });

      test('migrate returns source when sourceJson is null', () async {
        final result = await ConnectionMigration.migrate(
          secure: SecureStorageService(),
          sourceJson: null,
        );
        expect(result.json, isNull);
        expect(result.error, isNull);
      });

      test('backup and rollback on migrated primary validation failure', () async {
        final secure = SecureStorageService();
        // SecureStorage test map is in-memory and can be manipulated directly.
        final storage = SecureStorageService();
        final oldJson = jsonEncode([
          {
            'id': 'c1',
            'name': 'Server',
            'host': 'h',
            'username': 'u',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'tmuxPath': '/usr/bin/tmux',
          },
        ]);

        // Set source
        await storage.writeValue('connections', oldJson);

        // Read source, migrate, and then corrupt primary to simulate read-back mismatch.
        await ConnectionMigration.migrate(secure: secure, sourceJson: oldJson);

        // Now corrupt primary so that next migration sees invalid source.
        await storage.writeValue('connections', 'not-json');

        // Provide a valid backup.
        await storage.writeValue('connections_backup_v2', oldJson);

        final result = await ConnectionMigration.migrate(
          secure: secure,
          sourceJson: 'not-json',
        );

        expect(result.json, oldJson);
        expect(result.warning, isNotNull);
        expect(await secure.readValue('connections'), oldJson);
      });

      test('rolls back when primary read-back validation fails', () async {
        final storage = _CorruptOnSecondReadStorage();
        final oldJson = jsonEncode([
          {
            'id': 'c1',
            'name': 'Server',
            'host': 'h',
            'username': 'u',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'tmuxPath': '/usr/bin/tmux',
          },
        ]);

        final result = await ConnectionMigration.migrate(
          secure: storage,
          sourceJson: oldJson,
        );

        expect(result.error, isNotNull);
        expect(result.json, oldJson);
        expect(await storage.readValue('connections'), oldJson);
      });

      test('recovery from invalid source using stale backup', () async {
        final storage = SecureStorageService();
        final backupJson = jsonEncode([
          {
            'id': 'c1',
            'name': 'Server',
            'host': 'h',
            'username': 'u',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'multiplexer': {
              'backend': 'tmux',
              'executablePath': '/tmux',
            },
          },
        ]);

        await storage.writeValue('connections', 'totally invalid');
        await storage.writeValue('connections_backup_v2', backupJson);

        final result = await ConnectionMigration.migrate(
          secure: storage,
          sourceJson: 'totally invalid',
        );

        expect(result.json, backupJson);
        expect(result.warning, isNotNull);
        expect(await storage.readValue('connections'), backupJson);
      });
    });

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
            'multiplexer': {
              'backend': 'unknown',
              'executablePath': null,
            },
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

/// 1 回目の `connections` 読み込みで異なる値を返す [SecureStorageService] モック。
///
/// primary 書き込み後の read-back 検証失敗を再現する。
class _CorruptOnSecondReadStorage extends SecureStorageService {
  final _values = <String, String>{};
  var _connectionsReadCount = 0;

  @override
  Future<String?> readValue(String key) async {
    if (key == 'connections') {
      _connectionsReadCount++;
      if (_connectionsReadCount == 1) {
        return 'corrupted-json';
      }
    }
    return _values[key];
  }

  @override
  Future<void> writeValue(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> deleteValue(String key) async {
    _values.remove(key);
  }
}
