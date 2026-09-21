import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_lookup.dart';
import 'connection.dart';
import 'connection_storage.dart';
import 'connections_state.dart';

/// 接続一覧を管理するNotifier
class ConnectionsNotifier extends Notifier<ConnectionsState> {
  bool _disposed = false;

  /// 接続レコードの永続化（SecureStorage / SharedPreferences 移行 /
  /// ConnectionMigration / 破損判定は storage が担う）。
  late final ConnectionStorage _storage = ConnectionStorage();

  @override
  ConnectionsState build() {
    // 初期状態
    ref.onDispose(() => _disposed = true);
    _loadConnections();
    return const ConnectionsState(isLoading: true);
  }

  Future<void> _loadConnections() async {
    developer.log('_loadConnections() started', name: 'ConnectionsProvider');
    final result = await _storage.load(lookupL10n());
    if (!_disposed) {
      state = result;
    }
  }

  /// 接続を追加
  Future<void> add(Connection connection) async {
    developer.log(
      'add() called: ${connection.name} (${connection.id})',
      name: 'ConnectionsProvider',
    );
    developer.log(
      'Current connections count: ${state.connections.length}',
      name: 'ConnectionsProvider',
    );

    final connections = [...state.connections, connection];
    developer.log(
      'New connections count: ${connections.length}',
      name: 'ConnectionsProvider',
    );

    state = state.copyWith(
      connections: connections,
      corruptedRecords: const <CorruptedConnection>[],
      warning: null,
    );
    developer.log(
      'State updated, saving to secure storage...',
      name: 'ConnectionsProvider',
    );

    await _storage.save(connections);
    if (!_disposed) {
      developer.log(
        'Connections saved. Final count: ${state.connections.length}',
        name: 'ConnectionsProvider',
      );
    }
  }

  /// 接続を削除
  Future<void> remove(String id) async {
    developer.log('remove() called: $id', name: 'ConnectionsProvider');
    final connections = state.connections.where((c) => c.id != id).toList();
    state = state.copyWith(
      connections: connections,
      corruptedRecords: const <CorruptedConnection>[],
      warning: null,
    );
    await _storage.save(connections);
    if (!_disposed) {
      developer.log(
        'Connection removed. Remaining: ${state.connections.length}',
        name: 'ConnectionsProvider',
      );
    }
  }

  /// 接続を更新
  Future<void> update(Connection connection) async {
    developer.log(
      'update() called: ${connection.name} (${connection.id})',
      name: 'ConnectionsProvider',
    );
    final connections = state.connections.map((c) {
      return c.id == connection.id ? connection : c;
    }).toList();
    state = state.copyWith(
      connections: connections,
      corruptedRecords: const <CorruptedConnection>[],
      warning: null,
    );
    await _storage.save(connections);
    developer.log('Connection updated and saved', name: 'ConnectionsProvider');
  }

  /// 最終接続日時を更新
  Future<void> updateLastConnected(String id) async {
    final connections = state.connections.map((c) {
      if (c.id == id) {
        return c.copyWith(lastConnectedAt: DateTime.now());
      }
      return c;
    }).toList();
    state = state.copyWith(
      connections: connections,
      corruptedRecords: const <CorruptedConnection>[],
      warning: null,
    );
    await _storage.save(connections);
  }

  /// 接続を取得
  Connection? getById(String id) {
    try {
      return state.connections.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  /// deepLinkIdまたは接続名でサーバーを検索
  Connection? findByDeepLinkIdOrName(String serverIdentifier) {
    // まずdeepLinkIdで完全一致
    for (final c in state.connections) {
      if (c.deepLinkId != null && c.deepLinkId == serverIdentifier) {
        return c;
      }
    }
    // 次に接続名で完全一致
    for (final c in state.connections) {
      if (c.name == serverIdentifier) {
        return c;
      }
    }
    // 最後に接続名で大文字小文字無視の一致
    final lower = serverIdentifier.toLowerCase();
    for (final c in state.connections) {
      if (c.name.toLowerCase() == lower) {
        return c;
      }
    }
    return null;
  }

  /// リロード
  Future<void> reload() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      corruptedRecords: const <CorruptedConnection>[],
      warning: null,
    );
    await _loadConnections();
  }
}

/// 接続一覧プロバイダー
final connectionsProvider =
    NotifierProvider<ConnectionsNotifier, ConnectionsState>(() {
      return ConnectionsNotifier();
    });
