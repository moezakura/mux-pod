import '../../models/connection.dart';
import '../../models/auth_method.dart';
import '../keychain/secure_storage.dart';
import '../storage/connection_repository.dart';
import 'ssh_client.dart';

/// SSH認証サービス
///
/// 接続の認証方法に応じて適切な認証を行う。
class SshAuthService {
  SshAuthService({
    required SshClient sshClient,
    required ConnectionRepository connectionRepository,
    required SecureStorageService secureStorage,
  })  : _sshClient = sshClient,
        _connectionRepository = connectionRepository,
        _secureStorage = secureStorage;

  final SshClient _sshClient;
  final ConnectionRepository _connectionRepository;
  final SecureStorageService _secureStorage;

  /// 接続と認証を実行
  Future<void> connect(Connection connection) async {
    switch (connection.authMethod) {
      case PasswordAuth():
        await _connectWithPassword(connection);
      case KeyAuth(:final keyId):
        await _connectWithKey(connection, keyId);
    }
  }

  /// パスワード認証で接続
  Future<void> _connectWithPassword(Connection connection) async {
    final password = await _connectionRepository.getPassword(connection.id);
    if (password == null) {
      throw Exception('Password not found for connection: ${connection.id}');
    }

    await _sshClient.connectWithPassword(
      connection: connection,
      password: password,
    );
  }

  /// 鍵認証で接続
  Future<void> _connectWithKey(Connection connection, String keyId) async {
    final privateKey = await _secureStorage.getPrivateKey(keyId);
    if (privateKey == null) {
      throw Exception('Private key not found: $keyId');
    }

    // パスフレーズがあれば取得
    final passphrase = await _secureStorage.getPassphrase(keyId);

    await _sshClient.connectWithKey(
      connection: connection,
      privateKeyPem: privateKey,
      passphrase: passphrase,
    );
  }

  /// 接続テスト
  Future<bool> testConnection(Connection connection) async {
    try {
      await connect(connection);
      await _sshClient.disconnect(connection.id);
      return true;
    } catch (_) {
      return false;
    }
  }
}
