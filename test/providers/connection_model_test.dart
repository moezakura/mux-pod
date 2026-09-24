// P5: ConnectionProvider テスト（分割・責務: Connection モデルの JSON round trip・fromJson デフォルト/tmuxPath 相互運用・copyWith）。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';

import 'helpers/connection_test_storage.dart';

void main() {
  group('ConnectionProvider', () {
    setUp(resetConnectionStorage);

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
          'multiplexer': {'backend': 'unknown', 'executablePath': null},
        };

        expect(() => Connection.fromJson(json), throwsFormatException);
      });

      test(
        'copyWith multiplexer replaces whole object and clears executablePath',
        () {
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
        },
      );

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

      test('toJson writes current storageSchemaVersion (2)', () {
        final now = DateTime(2025, 1, 1);
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          createdAt: now,
        );

        final json = connection.toJson();
        expect(json['storageSchemaVersion'], 2);
      });

      test('toJson omits legacy tmuxPath when tmux path is auto-detected', () {
        final now = DateTime(2025, 1, 1);
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          createdAt: now,
        );

        final json = connection.toJson();
        expect(json, isNot(contains('tmuxPath')));
      });

      test(
        'toJson keeps legacy tmuxPath for custom tmux path (downgrade compat)',
        () {
          final now = DateTime(2025, 1, 1);
          final connection = Connection(
            id: 'c1',
            name: 'Server',
            host: 'h',
            username: 'u',
            multiplexer: const MultiplexerConfig.tmux('/usr/bin/tmux'),
            createdAt: now,
          );

          final json = connection.toJson();
          expect(json['tmuxPath'], '/usr/bin/tmux');
          expect(json['multiplexer']['executablePath'], '/usr/bin/tmux');
          expect(json['storageSchemaVersion'], 2);
        },
      );

      test('toJson omits tmuxPath for herdr backend', () {
        final now = DateTime(2025, 1, 1);
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          multiplexer: const MultiplexerConfig(
            backend: BackendType.herdr,
            executablePath: '/usr/local/bin/herdr',
          ),
          createdAt: now,
        );

        final json = connection.toJson();
        expect(json, isNot(contains('tmuxPath')));
        expect(json['multiplexer']['backend'], 'herdr');
        expect(json['multiplexer']['executablePath'], '/usr/local/bin/herdr');
      });

      test('fromJson defaults storageSchemaVersion to 1 when absent', () {
        final json = <String, dynamic>{
          'id': 'c1',
          'name': 'Server',
          'host': 'h',
          'username': 'u',
          'createdAt': '2025-01-01T00:00:00.000Z',
        };

        final restored = Connection.fromJson(json);
        expect(restored.storageSchemaVersion, 1);
      });

      test('fromJson reads storageSchemaVersion when present', () {
        final json = <String, dynamic>{
          'id': 'c1',
          'name': 'Server',
          'host': 'h',
          'username': 'u',
          'createdAt': '2025-01-01T00:00:00.000Z',
          'storageSchemaVersion': 2,
        };

        final restored = Connection.fromJson(json);
        expect(restored.storageSchemaVersion, 2);
      });

      test('copyWith preserves storageSchemaVersion', () {
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'h',
          username: 'u',
          storageSchemaVersion: 1,
          createdAt: DateTime(2025, 1, 1),
        );

        final renamed = connection.copyWith(name: 'Renamed');
        expect(renamed.storageSchemaVersion, 1);
      });

      test(
        'new-format record with tmuxPath loads via multiplexer (which wins)',
        () {
          final json = <String, dynamic>{
            'id': 'c1',
            'name': 'Server',
            'host': 'h',
            'username': 'u',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'storageSchemaVersion': 2,
            'tmuxPath': '/legacy/path',
            'multiplexer': {
              'backend': 'tmux',
              'executablePath': '/winner/path',
            },
          };

          final restored = Connection.fromJson(json);
          expect(restored.storageSchemaVersion, 2);
          expect(restored.multiplexer.executablePath, '/winner/path');
        },
      );
    });
  });
}
