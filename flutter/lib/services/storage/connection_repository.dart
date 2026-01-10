import '../../models/connection.dart';
import '../keychain/secure_storage.dart';
import 'storage_service.dart';

/// 接続設定リポジトリ
///
/// 接続設定の永続化を担当する。
/// - メタデータ: SharedPreferences
/// - パスワード: SecureStorage
class ConnectionRepository {
  ConnectionRepository({
    required StorageService storageService,
    required SecureStorageService secureStorage,
  })  : _storageService = storageService,
        _secureStorage = secureStorage;

  final StorageService _storageService;
  final SecureStorageService _secureStorage;

  static const String _connectionsKey = 'connections';

  /// 全接続取得
  Future<List<Connection>> getAll() async {
    final jsonList = _storageService.getJsonList(_connectionsKey);
    return jsonList.map((json) => Connection.fromJson(json)).toList();
  }

  /// 接続取得
  Future<Connection?> get(String id) async {
    final connections = await getAll();
    try {
      return connections.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 接続保存
  Future<void> save(Connection connection) async {
    final connections = await getAll();
    final index = connections.indexWhere((c) => c.id == connection.id);

    if (index >= 0) {
      connections[index] = connection;
    } else {
      connections.add(connection);
    }

    await _saveAll(connections);
  }

  /// 接続削除
  Future<void> delete(String id) async {
    final connections = await getAll();
    connections.removeWhere((c) => c.id == id);
    await _saveAll(connections);

    // パスワードも削除
    await _secureStorage.deletePassword(id);
  }

  /// パスワード保存
  Future<void> savePassword({
    required String connectionId,
    required String password,
  }) async {
    await _secureStorage.savePassword(
      connectionId: connectionId,
      password: password,
    );
  }

  /// パスワード取得
  Future<String?> getPassword(String connectionId) async {
    return await _secureStorage.getPassword(connectionId);
  }

  /// 最終接続日時更新
  Future<void> updateLastConnected(String connectionId) async {
    final connection = await get(connectionId);
    if (connection != null) {
      await save(connection.copyWith(
        lastConnected: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
  }

  /// 全接続を保存
  Future<void> _saveAll(List<Connection> connections) async {
    final jsonList = connections.map((c) => c.toJson()).toList();
    await _storageService.saveJsonList(_connectionsKey, jsonList);
  }

  /// 接続数取得
  Future<int> count() async {
    final connections = await getAll();
    return connections.length;
  }

  /// タグで検索
  Future<List<Connection>> findByTag(String tag) async {
    final connections = await getAll();
    return connections.where((c) => c.tags.contains(tag)).toList();
  }

  /// 全タグ取得
  Future<Set<String>> getAllTags() async {
    final connections = await getAll();
    final tags = <String>{};
    for (final connection in connections) {
      tags.addAll(connection.tags);
    }
    return tags;
  }
}
