import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import '../connection_error.dart';
import '../keychain/secure_storage.dart';
import 'ssh_authentication_error.dart';
import 'ssh_models.dart';

/// 接続確立の執行者。
///
/// ソケット接続・認証方式選択・ホスト鍵検証・鍵パース・fingerprint 移行を
/// 実行し、SSHClient / SSHSocket を生成する。結果は戻り値として返し、
/// 登録（attach）は facade が [SshResourceManager] に対して行う。
class SshConnector {
  SshConnector({
    required this.connectionFactory,
    required this.l10n,
    required this.setLastError,
  });

  /// 接続確立の注入（テスト用）。
  final Future<({SSHSocket socket, SSHClient client})> Function(
    String host,
    int port,
    String username,
    SshConnectOptions options,
    void Function() onAuthenticated,
    Future<bool> Function(String type, Uint8List fingerprint) onVerifyHostKey,
  )?
  connectionFactory;

  /// ローカライズ文字列プロバイダ（現在値を返すクロージャ）。
  final AppLocalizations? Function() l10n;

  /// lastError の書込先（フック。facade が state controller へ配線する）。
  final void Function(String?) setLastError;

  /// 旧形式（MD5 hex）保存値からの移行保留。
  ///
  /// dartssh2 2.18.0+ でホスト鍵 fingerprint が `SHA256:<base64>` の UTF-8 バイトに
  /// 変更された（BREAKING）。旧形式で保存済みの値は再検証できないため、
  /// 接続実績のあるサーバーとして受理し、**ユーザー認証成功後にのみ**
  /// 正規形式へ更新する（[applyPendingMigrationOnAuthenticated]）。
  ({String host, int port, String type, String fingerprint})?
  _pendingFingerprintMigration;

  /// 接続パラメータをバリデート（HEAD `SshClient._validateConnectionParams` 相当）。
  void validateConnectionParams(
    String host,
    int port,
    String username,
    SshConnectOptions options,
  ) {
    if (host.trim().isEmpty) {
      throw SshConnectionError(l10n()?.sshHostRequired ?? 'Host is required');
    }
    if (username.trim().isEmpty) {
      throw SshConnectionError(
        l10n()?.sshUsernameRequired ?? 'Username is required',
      );
    }
    if (port < 1 || port > 65535) {
      throw SshConnectionError(
        l10n()?.sshInvalidPortNumber(port) ?? 'Invalid port number: $port',
      );
    }
    if (options.password == null && options.privateKey == null) {
      throw SshAuthenticationError(
        l10n()?.sshCredentialRequired ??
            'Either password or privateKey must be provided',
      );
    }
  }

  /// SSH 接続を確立して接続資源を返す（HEAD `SshClient.connect` の接続部相当）。
  Future<({SSHSocket socket, SSHClient client})> connect({
    required String host,
    required int port,
    required String username,
    required SshConnectOptions options,
    required void Function() onAuthenticated,
  }) async {
    // 前回接続の移行保留をリセット（成功・失敗どちらでも次回に持ち越さない）
    _pendingFingerprintMigration = null;

    final factory = connectionFactory;
    if (factory != null) {
      final connection = await factory(
        host,
        port,
        username,
        options,
        onAuthenticated,
        (type, fingerprint) => _onVerifyHostKey(
          host,
          port,
          type,
          fingerprint,
          acceptNewHostKeys: options.acceptNewHostKeys,
        ),
      );
      return (socket: connection.socket, client: connection.client);
    }

    // ソケット接続
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: Duration(seconds: options.timeout),
    );

    // 認証方式に応じたクライアント作成
    final SSHClient client;
    if (options.privateKey != null) {
      // 鍵認証
      client = SSHClient(
        socket,
        username: username,
        keepAliveInterval: null,
        identities: _parsePrivateKey(options.privateKey!, options.passphrase),
        // inventory: SSH-LIFE-018
        onAuthenticated: onAuthenticated,
        onVerifyHostKey: (type, fingerprint) => _onVerifyHostKey(
          host,
          port,
          type,
          fingerprint,
          acceptNewHostKeys: options.acceptNewHostKeys,
        ),
      );
    } else if (options.password != null) {
      // パスワード認証
      client = SSHClient(
        socket,
        username: username,
        keepAliveInterval: null,
        onPasswordRequest: () => options.password!,
        onAuthenticated: onAuthenticated,
        onVerifyHostKey: (type, fingerprint) => _onVerifyHostKey(
          host,
          port,
          type,
          fingerprint,
          acceptNewHostKeys: options.acceptNewHostKeys,
        ),
      );
    } else {
      throw SshAuthenticationError('No authentication method provided');
    }
    return (socket: socket, client: client);
  }

  // inventory: SSH-LIFE-017
  /// ホスト鍵フィンガープリントを検証する。
  ///
  /// dartssh2 2.18.0 以降は OpenSSH 形式 `SHA256:<base64>` 文字列の UTF-8 バイトが
  /// 渡される（2.18.0 で BREAKING: それ以前は MD5 生バイト）。
  ///
  /// - 初回接続時: [acceptNewHostKeys] が true なら受け入れて保存し、
  ///   false なら拒否する。
  /// - 保存値が正規形式（`SHA256:` プレフィックス）: 比較して一致なら受理、
  ///   不一致なら拒否。
  /// - 保存値が旧形式（MD5 hex・`SHA256:` プレフィックスなし）: 再検証不能なため
  ///   接続実績のあるサーバーとして受理し、[connect] がユーザー認証成功後に
  ///   正規形式へ更新する（[_pendingFingerprintMigration]）。
  Future<bool> _onVerifyHostKey(
    String host,
    int port,
    String type,
    Uint8List fingerprint, {
    required bool acceptNewHostKeys,
  }) async {
    final formatted = utf8.decode(fingerprint, allowMalformed: true);

    final storage = SecureStorageService();
    final known = await storage.getHostKeyFingerprint(host, port, type);

    if (known == null) {
      if (acceptNewHostKeys) {
        await storage.saveHostKeyFingerprint(host, port, type, formatted);
        return true;
      }
      setLastError('Unknown host key: $host:$port ($type)');
      return false;
    }

    if (!known.startsWith('SHA256:')) {
      // 旧形式（MD5 hex）の保存値。認証成功後に正規形式へ更新する。
      if (acceptNewHostKeys) {
        _pendingFingerprintMigration = (
          host: host,
          port: port,
          type: type,
          fingerprint: formatted,
        );
        return true;
      }
      setLastError('Unknown host key: $host:$port ($type)');
      return false;
    }

    if (known == formatted) {
      return true;
    }

    setLastError(
      'Host key verification failed: $host:$port ($type) fingerprint changed',
    );
    return false;
  }

  /// 秘密鍵をパース
  List<SSHKeyPair> _parsePrivateKey(String privateKey, String? passphrase) {
    try {
      // SSHKeyPair.fromPem は List<SSHKeyPair> を返す
      final keyPairs = SSHKeyPair.fromPem(privateKey, passphrase);
      if (keyPairs.isEmpty) {
        throw SshAuthenticationError(
          l10n()?.sshNoValidKeyInPem ?? 'No valid key found in PEM data',
        );
      }
      return keyPairs;
    } on FormatException catch (e) {
      throw SshAuthenticationError(
        l10n()?.sshInvalidPrivateKeyFormat(e.message) ??
            'Invalid private key format: ${e.message}',
      );
    } catch (e) {
      if (e is SshAuthenticationError) rethrow;
      if (passphrase == null && privateKey.contains('ENCRYPTED')) {
        throw SshAuthenticationError(
          l10n()?.sshPrivateKeyEncrypted ??
              'Private key is encrypted, passphrase required',
        );
      }
      throw SshAuthenticationError(
        l10n()?.sshParsePrivateKeyFailed(e.toString()) ??
            'Failed to parse private key: $e',
      );
    }
  }

  /// ユーザー認証成功後に旧形式保存値を正規形式へ更新する
  /// （HEAD `SshClient.connect` 内の移行適用相当）。
  Future<void> applyPendingMigrationOnAuthenticated() async {
    final pending = _pendingFingerprintMigration;
    _pendingFingerprintMigration = null;
    if (pending != null) {
      await SecureStorageService().saveHostKeyFingerprint(
        pending.host,
        pending.port,
        pending.type,
        pending.fingerprint,
      );
    }
  }
}
