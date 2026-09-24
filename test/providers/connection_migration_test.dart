// P5: ConnectionProvider テスト（分割・責務: legacy→multiplexer 移行・v2 スキップ・backup/rollback・stale backup 復帰）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/connection/connection_migration.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';

import 'helpers/connection_test_storage.dart';

void main() {
  group('ConnectionProvider', () {
    setUp(resetConnectionStorage);

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
        expect(
          migratedList[0]['multiplexer']['executablePath'],
          '/usr/bin/tmux',
        );
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
            'multiplexer': {'backend': 'tmux', 'executablePath': '/winner'},
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
            'multiplexer': {'backend': 'tmux', 'executablePath': '/tmux'},
          },
        ]);

        final result = await ConnectionMigration.migrate(
          secure: secure,
          sourceJson: newJson,
        );

        expect(result.json, newJson);
        expect(await secure.readValue('connections_backup_v2'), isNull);
      });

      test(
        'migrate skips v2 records even when tmuxPath is present (downgrade compat)',
        () async {
          final secure = SecureStorageService();
          final v2Json = jsonEncode([
            {
              'id': 'c1',
              'name': 'Server',
              'host': 'h',
              'username': 'u',
              'createdAt': '2025-01-01T00:00:00.000Z',
              'storageSchemaVersion': 2,
              'multiplexer': {
                'backend': 'tmux',
                'executablePath': '/usr/bin/tmux',
              },
              'tmuxPath': '/usr/bin/tmux',
            },
          ]);

          final result = await ConnectionMigration.migrate(
            secure: secure,
            sourceJson: v2Json,
          );

          // 新形式（schema 番号あり）は migration 不要として source がそのまま返る
          expect(result.error, isNull);
          expect(result.json, v2Json);
          // backup は作成されず、primary も書き換えられない
          expect(await secure.readValue('connections_backup_v2'), isNull);
          expect(await secure.readValue('connections'), isNull);
        },
      );

      test(
        'migrate with mixed v2 and legacy records migrates only legacy records',
        () async {
          final secure = SecureStorageService();
          final mixedJson = jsonEncode([
            {
              'id': 'c1',
              'name': 'V2',
              'host': 'h1',
              'username': 'u1',
              'createdAt': '2025-01-01T00:00:00.000Z',
              'storageSchemaVersion': 2,
              'multiplexer': {'backend': 'tmux', 'executablePath': '/winner'},
              'tmuxPath': '/downgrade-compat',
            },
            {
              'id': 'c2',
              'name': 'Legacy',
              'host': 'h2',
              'username': 'u2',
              'createdAt': '2025-01-02T00:00:00.000Z',
              'tmuxPath': '/legacy/tmux',
            },
          ]);

          final result = await ConnectionMigration.migrate(
            secure: secure,
            sourceJson: mixedJson,
          );

          expect(result.error, isNull);
          final migratedList = jsonDecode(result.json!) as List<dynamic>;
          expect(migratedList, hasLength(2));

          // v2 レコードはスキップされ、downgrade 互換の tmuxPath を保持する
          final v2 = migratedList[0] as Map<String, dynamic>;
          expect(v2['storageSchemaVersion'], 2);
          expect(v2['tmuxPath'], '/downgrade-compat');
          expect(
            (v2['multiplexer'] as Map<String, dynamic>)['executablePath'],
            '/winner',
          );

          // 旧形式レコードのみ migration される
          final legacy = migratedList[1] as Map<String, dynamic>;
          expect(legacy, isNot(contains('tmuxPath')));
          expect(
            (legacy['multiplexer'] as Map<String, dynamic>)['backend'],
            'tmux',
          );
          expect(
            (legacy['multiplexer'] as Map<String, dynamic>)['executablePath'],
            '/legacy/tmux',
          );

          // backup は成功後に削除され、primary には migration 済み JSON が書かれる
          expect(await secure.readValue('connections_backup_v2'), isNull);
          expect(await secure.readValue('connections'), result.json);
        },
      );

      test(
        'provider reload does not re-migrate v2 data with downgrade-compat tmuxPath',
        () async {
          final storage = SecureStorageService();
          // toJson() は storageSchemaVersion=2 と tmuxPath の両方を書き出す
          final connection = Connection(
            id: 'c1',
            name: 'Server',
            host: 'h',
            username: 'u',
            multiplexer: const MultiplexerConfig.tmux('/usr/bin/tmux'),
            createdAt: DateTime(2025, 1, 1),
          );
          final json = jsonEncode([connection.toJson()]);
          expect(jsonDecode(json) as List, hasLength(1));
          await storage.writeValue('connections', json);

          final container = ProviderContainer();
          addTearDown(container.dispose);
          await container.read(connectionsProvider.notifier).reload();

          final state = container.read(connectionsProvider);
          expect(state.connections, hasLength(1));
          expect(
            state.connections[0].multiplexer.executablePath,
            '/usr/bin/tmux',
          );
          expect(state.corruptedRecords, isEmpty);
          // migration が走らないため backup は作られない
          expect(await storage.readValue('connections_backup_v2'), isNull);
        },
      );

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
            'multiplexer': {'backend': 'tmux', 'executablePath': '/tmux'},
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

    /// 1 回目の `connections` 読み込みで異なる値を返す [SecureStorageService] モック。
    ///
    /// primary 書き込み後の read-back 検証失敗を再現する。
  });
}

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
