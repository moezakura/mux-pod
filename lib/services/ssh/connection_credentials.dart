import '../keychain/secure_storage.dart';
import 'ssh_client.dart';

/// Builds [SshConnectOptions] from a stored connection's credentials.
///
/// Centralizes the key-vs-password credential resolution shared by
/// providers that open ad-hoc SSH connections (Remote UI, alert panes).
class ConnectionCredentials {
  ConnectionCredentials._();

  /// Resolves the credentials for a connection described by [authMethod]
  /// (`'key'` or `'password'`), [keyId] and [connectionId] into
  /// [SshConnectOptions].
  static Future<SshConnectOptions> resolve({
    required String connectionId,
    required String authMethod,
    String? keyId,
    String? tmuxPath,
    SecureStorageService? storage,
  }) async {
    final store = storage ?? SecureStorageService();
    if (authMethod == 'key' && keyId != null) {
      return SshConnectOptions(
        privateKey: await store.getPrivateKey(keyId),
        passphrase: await store.getPassphrase(keyId),
        tmuxPath: tmuxPath,
      );
    }
    return SshConnectOptions(
      password: await store.getPassword(connectionId),
      tmuxPath: tmuxPath,
    );
  }
}
