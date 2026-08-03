import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
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
      expect(state.error, isNull);
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

    test('Connection JSON round trip with defaults', () {
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
    });

    test('Connection fromJson fills missing fields', () {
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
  });
}
