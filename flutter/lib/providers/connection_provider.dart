import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/auth_method.dart';
import '../models/connection.dart';
import '../services/keychain/secure_storage.dart';
import '../services/storage/connection_repository.dart';
import '../services/storage/storage_service.dart';

/// StorageService プロバイダー
final storageServiceProvider = Provider<StorageService>((ref) {
  final service = StorageService();
  // 初期化は別途行う必要あり
  return service;
});

/// SecureStorageService プロバイダー
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// ConnectionRepository プロバイダー
final connectionRepositoryProvider = Provider<ConnectionRepository>((ref) {
  return ConnectionRepository(
    storageService: ref.watch(storageServiceProvider),
    secureStorage: ref.watch(secureStorageServiceProvider),
  );
});

/// 接続一覧プロバイダー
final connectionsProvider =
    AsyncNotifierProvider<ConnectionsNotifier, List<Connection>>(
  ConnectionsNotifier.new,
);

/// 接続一覧Notifier
class ConnectionsNotifier extends AsyncNotifier<List<Connection>> {
  @override
  Future<List<Connection>> build() async {
    return await _repository.getAll();
  }

  ConnectionRepository get _repository =>
      ref.read(connectionRepositoryProvider);

  /// 接続追加
  Future<Connection> add({
    required String name,
    required String host,
    required int port,
    required String username,
    required AuthMethod authMethod,
    String? password,
    String? keyId,
    int timeout = 30,
    int keepAliveInterval = 60,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final connection = Connection(
      id: const Uuid().v4(),
      name: name,
      host: host,
      port: port,
      username: username,
      authMethod: authMethod,
      keyId: keyId,
      timeout: timeout,
      keepAliveInterval: keepAliveInterval,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );

    await _repository.save(connection);

    if (password != null) {
      await _repository.savePassword(
        connectionId: connection.id,
        password: password,
      );
    }

    ref.invalidateSelf();
    return connection;
  }

  /// 接続更新
  Future<void> updateConnection(Connection connection) async {
    await _repository.save(connection.copyWith(
      updatedAt: DateTime.now(),
    ));
    ref.invalidateSelf();
  }

  /// パスワード更新
  Future<void> updatePassword({
    required String connectionId,
    required String password,
  }) async {
    await _repository.savePassword(
      connectionId: connectionId,
      password: password,
    );
  }

  /// 接続削除
  Future<void> delete(String id) async {
    await _repository.delete(id);
    ref.invalidateSelf();
  }

  /// 接続テスト
  Future<bool> testConnection(String connectionId) async {
    // TODO: SSHサービスを使って接続テスト
    return false;
  }
}

/// 単一接続プロバイダー
final connectionProvider =
    FutureProvider.family<Connection?, String>((ref, id) async {
  final repository = ref.watch(connectionRepositoryProvider);
  return await repository.get(id);
});
