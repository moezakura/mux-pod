// Regression tests for immediate-reflect behaviour of ConnectionsScreen.
//
// PR #46 removed ref.invalidate(connectionsProvider) from the
// _addConnection() and _editConnection() callsites.  The fix relies on
// ConnectionsNotifier.add() / update() mutating state directly, so any
// ProviderContainer that watches connectionsProvider sees the new value
// without a full provider rebuild cycle.
//
// Widget-level testing of ConnectionsScreen is out of scope here because
// the screen depends on many platform-specific providers (SSH, secure
// storage, etc.).  These notifier-level tests give the same safety net
// with far less setup.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Connection _makeConnection({
  String id = 'c1',
  String name = 'Test Server',
  String host = '10.0.0.1',
}) {
  return Connection(
    id: id,
    name: name,
    host: host,
    port: 22,
    username: 'user',
    createdAt: DateTime(2024),
  );
}

/// Triggers the provider (causing build() to fire) and then drains the
/// event queue so that _loadConnections() runs to completion.
///
/// build() returns ConnectionsState(isLoading: true) synchronously and
/// fires _loadConnections() as a side-effect.  _loadConnections() contains
/// multiple await points (SharedPreferences.getInstance, prefs.getString,
/// etc.), so we must pump the full event queue *after* the provider has
/// been activated to ensure the loading flag is cleared before assertions.
Future<void> _activateAndLoad(ProviderContainer container) async {
  // Touch the provider so build() is called and _loadConnections() starts.
  container.read(connectionsProvider);
  // Drain all pending microtasks / timer callbacks.
  await pumpEventQueue();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Start each test with empty shared preferences so _loadConnections()
    // returns an empty list quickly.
    SharedPreferences.setMockInitialValues({});
  });

  group('ConnectionsNotifier.add() — immediate reflect', () {
    test('state.connections is empty before any add()', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Activate the provider then flush async I/O so _loadConnections()
      // completes and sets isLoading to false.
      await _activateAndLoad(container);

      final state = container.read(connectionsProvider);
      // After load with empty SharedPreferences the list must be empty and
      // the loading flag must be cleared.
      expect(state.connections, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('add() updates state before the caller observes the result', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      final notifier = container.read(connectionsProvider.notifier);
      final conn = _makeConnection();

      // add() sets state synchronously (before awaiting _saveConnections),
      // so by the time the returned Future resolves the state is already
      // visible to any reader.
      await notifier.add(conn);

      final state = container.read(connectionsProvider);
      expect(state.connections, hasLength(1));
      expect(state.connections.first.id, equals('c1'));
    });

    test('watchers see the new connection after add() without invalidate',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      // Subscribe a listener that records build counts.
      int buildCount = 0;
      container.listen<ConnectionsState>(
        connectionsProvider,
        (_, __) => buildCount++,
      );

      final notifier = container.read(connectionsProvider.notifier);
      await notifier.add(_makeConnection());

      // At least one notification must have fired (the state change).
      expect(buildCount, greaterThanOrEqualTo(1));

      final state = container.read(connectionsProvider);
      expect(state.connections, hasLength(1));
      expect(state.connections.first.name, equals('Test Server'));
    });

    test('adding two connections accumulates both in state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      final notifier = container.read(connectionsProvider.notifier);
      await notifier.add(_makeConnection(id: 'c1', name: 'Server A'));
      await notifier.add(_makeConnection(id: 'c2', name: 'Server B'));

      final state = container.read(connectionsProvider);
      expect(state.connections, hasLength(2));
      final ids = state.connections.map((c) => c.id).toSet();
      expect(ids, containsAll(['c1', 'c2']));
    });
  });

  group('ConnectionsNotifier.update() — immediate reflect', () {
    test('update() replaces the entry in state immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      final notifier = container.read(connectionsProvider.notifier);

      // Seed one connection.
      await notifier.add(_makeConnection(id: 'c1', name: 'Original'));

      // Mutate it.
      final updated = _makeConnection(id: 'c1', name: 'Updated');
      await notifier.update(updated);

      final state = container.read(connectionsProvider);
      expect(state.connections, hasLength(1));
      expect(state.connections.first.name, equals('Updated'));
    });

    test('watchers see the updated connection after update() without invalidate',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      final notifier = container.read(connectionsProvider.notifier);
      await notifier.add(_makeConnection(id: 'c1', name: 'Before'));

      int updateNotifications = 0;
      container.listen<ConnectionsState>(
        connectionsProvider,
        (_, __) => updateNotifications++,
      );

      await notifier.update(_makeConnection(id: 'c1', name: 'After'));

      expect(updateNotifications, greaterThanOrEqualTo(1));

      final state = container.read(connectionsProvider);
      expect(state.connections.first.name, equals('After'));
    });

    test('update() does not affect other connections', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      final notifier = container.read(connectionsProvider.notifier);
      await notifier.add(_makeConnection(id: 'c1', name: 'A'));
      await notifier.add(_makeConnection(id: 'c2', name: 'B'));

      await notifier.update(_makeConnection(id: 'c1', name: 'A-edited'));

      final state = container.read(connectionsProvider);
      expect(state.connections, hasLength(2));

      final c1 = state.connections.firstWhere((c) => c.id == 'c1');
      final c2 = state.connections.firstWhere((c) => c.id == 'c2');
      expect(c1.name, equals('A-edited'));
      expect(c2.name, equals('B'));
    });
  });

  group('filteredConnectionsProvider — derived state updates without rebuild',
      () {
    test('derived provider reflects add() immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      final notifier = container.read(connectionsProvider.notifier);

      // Initially empty.
      expect(container.read(filteredConnectionsProvider), isEmpty);

      await notifier.add(_makeConnection(id: 'c1', name: 'My Server'));

      // Derived provider must return the new entry without invalidate.
      final filtered = container.read(filteredConnectionsProvider);
      expect(filtered, hasLength(1));
      expect(filtered.first.name, equals('My Server'));
    });

    test('derived provider reflects update() immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _activateAndLoad(container);

      final notifier = container.read(connectionsProvider.notifier);
      await notifier.add(_makeConnection(id: 'c1', name: 'Before'));

      await notifier.update(_makeConnection(id: 'c1', name: 'After'));

      final filtered = container.read(filteredConnectionsProvider);
      expect(filtered.first.name, equals('After'));
    });
  });
}
