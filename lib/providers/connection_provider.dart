import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend/multiplexer_config.dart';
import '../services/connection/connection_migration.dart';
import '../services/keychain/secure_storage.dart';

/// 接続設定
class Connection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authMethod; // 'password' | 'key'
  final String? keyId;

  /// 使用する multiplexer の設定。
  final MultiplexerConfig multiplexer;

  final DateTime createdAt;
  final DateTime? lastConnectedAt;

  /// ディープリンク用の識別子（外部スクリプトと共有可能）
  final String? deepLinkId;

  Connection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = 'password',
    this.keyId,
    MultiplexerConfig? multiplexer,
    required this.createdAt,
    this.lastConnectedAt,
    this.deepLinkId,
  }) : multiplexer = multiplexer ?? const MultiplexerConfig.tmux();

  Connection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? authMethod,
    String? keyId,
    MultiplexerConfig? multiplexer,
    DateTime? createdAt,
    DateTime? lastConnectedAt,
    String? deepLinkId,
    bool clearDeepLinkId = false,
  }) {
    return Connection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      keyId: keyId ?? this.keyId,
      multiplexer: multiplexer ?? this.multiplexer,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      deepLinkId: clearDeepLinkId ? null : (deepLinkId ?? this.deepLinkId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authMethod': authMethod,
      'keyId': keyId,
      'multiplexer': multiplexer.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'deepLinkId': deepLinkId,
    };
  }

  factory Connection.fromJson(Map<String, dynamic> json) {
    final multiplexerJson = json['multiplexer'] as Map<String, dynamic>?;
    final tmuxPath = json['tmuxPath'] as String?;
    final MultiplexerConfig multiplexer;
    if (multiplexerJson != null) {
      multiplexer = MultiplexerConfig.fromJson(multiplexerJson);
    } else if (tmuxPath != null && tmuxPath.isNotEmpty) {
      multiplexer = MultiplexerConfig.tmux(tmuxPath);
    } else {
      multiplexer = const MultiplexerConfig.tmux();
    }

    return Connection(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      authMethod: json['authMethod'] as String? ?? 'password',
      keyId: json['keyId'] as String?,
      multiplexer: multiplexer,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'] as String)
          : null,
      deepLinkId: json['deepLinkId'] as String?,
    );
  }
}

/// 読み込めなかった破損レコードの情報。
class CorruptedConnection {
  /// 読み込めた ID（ない場合もある）。
  final String? id;

  /// 破損理由（非機密）。
  final String reason;

  /// 元の JSON レコード（デバッグ・回復用）。
  final Map<String, dynamic>? rawJson;

  const CorruptedConnection({
    this.id,
    required this.reason,
    this.rawJson,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reason': reason,
      'rawJson': rawJson,
    };
  }
}

/// 接続一覧の状態
class ConnectionsState {
  final List<Connection> connections;
  final bool isLoading;
  final String? error;

  /// 読み込めなかった破損レコード一覧。
  final List<CorruptedConnection> corruptedRecords;

  /// ユーザー向けの非機密警告（マイグレーションや破損レカウント）。
  final String? warning;

  static const Object _kKeepSentinel = Object();

  const ConnectionsState({
    this.connections = const [],
    this.isLoading = false,
    this.error,
    this.corruptedRecords = const [],
    this.warning,
  });

  ConnectionsState copyWith({
    List<Connection>? connections,
    bool? isLoading,
    String? error,
    List<CorruptedConnection>? corruptedRecords,
    Object? warning = _kKeepSentinel,
  }) {
    return ConnectionsState(
      connections: connections ?? this.connections,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      corruptedRecords: corruptedRecords ?? this.corruptedRecords,
      warning: warning == _kKeepSentinel ? this.warning : warning as String?,
    );
  }
}

/// 接続一覧を管理するNotifier
class ConnectionsNotifier extends Notifier<ConnectionsState> {
  static const String _storageKey = 'connections';
  bool _disposed = false;

  @override
  ConnectionsState build() {
    // 初期状態
    ref.onDispose(() => _disposed = true);
    _loadConnections();
    return const ConnectionsState(isLoading: true);
  }

  Future<void> _loadConnections() async {
    developer.log('_loadConnections() started', name: 'ConnectionsProvider');
    try {
      final secure = SecureStorageService();
      String? jsonString = await secure.readValue(_storageKey);

      // 古いSharedPreferencesからの移行
      SharedPreferences? prefs;
      var fromSharedPreferences = false;
      if (jsonString == null) {
        prefs = await SharedPreferences.getInstance();
        final sharedPrefsJson = prefs.getString(_storageKey);
        if (sharedPrefsJson != null) {
          await secure.writeValue(_storageKey, sharedPrefsJson);
          jsonString = sharedPrefsJson;
          fromSharedPreferences = true;
          developer.log('Copied connections from SharedPreferences to secure storage for migration', name: 'ConnectionsProvider');
        }
      }

      developer.log('JSON from storage: ${jsonString != null ? 'exists' : 'null'}', name: 'ConnectionsProvider');

      // 旧 tmuxPath から multiplexer へのマイグレーション
      final migrationResult = await ConnectionMigration.migrate(
        secure: secure,
        sourceJson: jsonString,
      );

      // SharedPreferences コピーは schema migration が成功してから削除
      if (fromSharedPreferences &&
          migrationResult.error == null &&
          migrationResult.json != null) {
        await prefs?.remove(_storageKey);
        developer.log('Removed migrated SharedPreferences copy', name: 'ConnectionsProvider');
      }

      if (migrationResult.error != null && migrationResult.json == null) {
        developer.log('Migration error: ${migrationResult.error}', name: 'ConnectionsProvider');
        if (!_disposed) {
          state = ConnectionsState(
            error: migrationResult.error,
            warning: migrationResult.warning,
          );
        }
        return;
      }

      jsonString = migrationResult.json;

      if (jsonString != null) {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        final connections = <Connection>[];
        final corruptedRecords = <CorruptedConnection>[];

        for (final record in jsonList) {
          try {
            if (record is! Map<String, dynamic>) {
              throw FormatException('Record is not a JSON object');
            }
            connections.add(Connection.fromJson(record));
          } catch (e, stackTrace) {
            developer.log('Corrupted connection record: $e', name: 'ConnectionsProvider', error: e, stackTrace: stackTrace);
            final id = record is Map<String, dynamic> ? record['id'] as String? : null;
            corruptedRecords.add(CorruptedConnection(
              id: id,
              reason: 'Failed to load connection record: $e',
              rawJson: record is Map<String, dynamic> ? record : null,
            ));
          }
        }

        developer.log('Loaded ${connections.length} healthy and ${corruptedRecords.length} corrupted connection records from storage', name: 'ConnectionsProvider');

        // 最終接続日時で並び替え（降順）
        connections.sort((a, b) {
          final aTime = a.lastConnectedAt ?? a.createdAt;
          final bTime = b.lastConnectedAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        });

        String? warning;
        if (corruptedRecords.isNotEmpty) {
          warning = '${corruptedRecords.length} connections could not be loaded.';
        }
        if (migrationResult.warning != null) {
          warning = warning == null
              ? migrationResult.warning
              : '$warning ${migrationResult.warning}';
        }

        if (!_disposed) {
          state = ConnectionsState(
            connections: connections,
            corruptedRecords: corruptedRecords,
            warning: warning,
            error: migrationResult.error,
          );
        }
        developer.log('State updated with ${connections.length} connections, ${corruptedRecords.length} corrupted records', name: 'ConnectionsProvider');
      } else {
        if (!_disposed) {
          state = ConnectionsState(
            warning: migrationResult.warning,
          );
        }
        developer.log('No saved connections, initialized empty state', name: 'ConnectionsProvider');
      }
    } catch (e, stackTrace) {
      developer.log('Error loading connections: $e', name: 'ConnectionsProvider', error: e, stackTrace: stackTrace);
      if (!_disposed) {
        state = ConnectionsState(error: e.toString());
      }
    }
  }

  Future<void> _saveConnections(List<Connection> connections) async {
    final secure = SecureStorageService();
    final jsonList = connections.map((c) => c.toJson()).toList();
    await secure.writeValue(_storageKey, jsonEncode(jsonList));
  }

  /// 接続を追加
  Future<void> add(Connection connection) async {
    developer.log('add() called: ${connection.name} (${connection.id})', name: 'ConnectionsProvider');
    developer.log('Current connections count: ${state.connections.length}', name: 'ConnectionsProvider');

    final connections = [...state.connections, connection];
    developer.log('New connections count: ${connections.length}', name: 'ConnectionsProvider');

    state = state.copyWith(
      connections: connections,
      corruptedRecords: const <CorruptedConnection>[],
      warning: null,
    );
    developer.log('State updated, saving to secure storage...', name: 'ConnectionsProvider');

    await _saveConnections(connections);
    if (!_disposed) {
      developer.log('Connections saved. Final count: ${state.connections.length}', name: 'ConnectionsProvider');
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
    await _saveConnections(connections);
    if (!_disposed) {
      developer.log('Connection removed. Remaining: ${state.connections.length}', name: 'ConnectionsProvider');
    }
  }

  /// 接続を更新
  Future<void> update(Connection connection) async {
    developer.log('update() called: ${connection.name} (${connection.id})', name: 'ConnectionsProvider');
    final connections = state.connections.map((c) {
      return c.id == connection.id ? connection : c;
    }).toList();
    state = state.copyWith(
      connections: connections,
      corruptedRecords: const <CorruptedConnection>[],
      warning: null,
    );
    await _saveConnections(connections);
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
    await _saveConnections(connections);
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

/// 選択中接続IDを管理するNotifier
class SelectedConnectionIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) {
    state = id;
  }
}

/// 検索クエリを管理するNotifier
class ConnectionSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

/// 検索クエリプロバイダー
final connectionSearchProvider =
    NotifierProvider<ConnectionSearchNotifier, String>(() {
  return ConnectionSearchNotifier();
});

/// ソートオプション
enum ConnectionSortOption {
  nameAsc,
  nameDesc,
  lastConnectedDesc,
  lastConnectedAsc,
  hostAsc,
  hostDesc,
}

/// ソートオプションを管理するNotifier
class ConnectionSortNotifier extends Notifier<ConnectionSortOption> {
  @override
  ConnectionSortOption build() => ConnectionSortOption.lastConnectedDesc;

  void setSort(ConnectionSortOption option) {
    state = option;
  }
}

/// ソートオプションプロバイダー
final connectionSortProvider =
    NotifierProvider<ConnectionSortNotifier, ConnectionSortOption>(() {
  return ConnectionSortNotifier();
});

/// フィルタリング・ソート済み接続リストプロバイダー
final filteredConnectionsProvider = Provider<List<Connection>>((ref) {
  final connectionsState = ref.watch(connectionsProvider);
  final searchQuery = ref.watch(connectionSearchProvider).toLowerCase();
  final sortOption = ref.watch(connectionSortProvider);

  // 検索フィルタリング（元のリストを変更しないようコピーを作成）
  var connections = List.of(connectionsState.connections);
  if (searchQuery.isNotEmpty) {
    connections = connections.where((c) {
      return c.name.toLowerCase().contains(searchQuery) ||
          c.host.toLowerCase().contains(searchQuery) ||
          c.username.toLowerCase().contains(searchQuery) ||
          (c.deepLinkId?.toLowerCase().contains(searchQuery) ?? false);
    }).toList();
  }

  // ソート
  switch (sortOption) {
    case ConnectionSortOption.nameAsc:
      connections.sort((a, b) => a.name.compareTo(b.name));
    case ConnectionSortOption.nameDesc:
      connections.sort((a, b) => b.name.compareTo(a.name));
    case ConnectionSortOption.lastConnectedDesc:
      connections.sort((a, b) {
        final aTime = a.lastConnectedAt ?? a.createdAt;
        final bTime = b.lastConnectedAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });
    case ConnectionSortOption.lastConnectedAsc:
      connections.sort((a, b) {
        final aTime = a.lastConnectedAt ?? a.createdAt;
        final bTime = b.lastConnectedAt ?? b.createdAt;
        return aTime.compareTo(bTime);
      });
    case ConnectionSortOption.hostAsc:
      connections.sort((a, b) => a.host.compareTo(b.host));
    case ConnectionSortOption.hostDesc:
      connections.sort((a, b) => b.host.compareTo(a.host));
  }

  return connections;
});

/// 現在選択中の接続IDプロバイダー
final selectedConnectionIdProvider =
    NotifierProvider<SelectedConnectionIdNotifier, String?>(() {
  return SelectedConnectionIdNotifier();
});

/// 現在選択中の接続プロバイダー
final selectedConnectionProvider = Provider<Connection?>((ref) {
  final id = ref.watch(selectedConnectionIdProvider);
  if (id == null) return null;

  final state = ref.watch(connectionsProvider);
  try {
    return state.connections.firstWhere((c) => c.id == id);
  } catch (e) {
    return null;
  }
});
