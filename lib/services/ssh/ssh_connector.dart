import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import '../connection_error.dart';
import '../connection/proxy_config.dart';
import '../keychain/secure_storage.dart';
import 'ssh_authentication_error.dart';
import 'ssh_models.dart';
import 'ssh_proxy_tunneler.dart';

/// 接続確立の執行者。
///
/// ソケット接続・認証方式選択・ホスト鍵検証・鍵パース・fingerprint 移行を
/// 実行し、SSHClient / SSHSocket を生成する。結果は戻り値として返し、
/// 登録（attach）は facade が [SshResourceManager] に対して行う。
/// `options.proxy != null` の場合はソケット生成を [SshProxyTunneler] へ
/// 委譲する（target の SSHClient 組立はどちらの経路もこのクラスが担当）。
class SshConnector {
  SshConnector({
    required this.connectionFactory,
    required this.l10n,
    required this.setLastError,
    SshProxyTunneler? tunneler,
    this.socketDialer = SSHSocket.connect,
  }) : _tunneler = tunneler ??
           SshProxyTunneler(l10n: l10n, socketDialer: socketDialer);

  /// 接続確立の注入（テスト用）。
  ///
  /// **型契約は不変**（Issue #56 で拡張しない）: factory は「ダイヤルを含む
  /// 接続全体のすり替え」の意味論のため、jump は存在せず、戻り record は
  /// `jumpClients: const []` として包まれる。
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

  /// 直接接続経路のソケットダイヤル（テスト用注入・既定は実物）。
  final SshProxySocketDialer socketDialer;

  /// ジャンプ経路のトンネル構築者（未注入時は本番実装）。
  final SshProxyTunneler _tunneler;

  /// 旧形式（MD5 hex）保存値からの移行保留。
  ///
  /// dartssh2 2.18.0+ でホスト鍵 fingerprint が `SHA256:<base64>` の UTF-8 バイトに
  /// 変更された（BREAKING）。旧形式で保存済みの値は再検証できないため、
  /// 接続実績のあるサーバーとして受理し、**ユーザー認証成功後にのみ**
  /// 正規形式へ更新する（[applyPendingMigrationOnAuthenticated]）。
  ///
  /// jump + target の両方が旧形式で保留になる（跳び先検証が先に起きる）ため
  /// List で保持する。
  List<({String host, int port, String type, String fingerprint})>?
  _pendingFingerprintMigrations;

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
    _validateProxy(options.proxy);
  }

  /// ジャンプ経路の接続前検証（MR-7・転送先 M6）。
  ///
  /// hop host 非空 / port 1..65535 / username 非空 / credential 存在 /
  /// hops 非空 / 上限 [maxProxyHops] / hops 内 host:port 重複拒否 /
  /// forwardHost 非空なら forwardPort 1..65535。runtime 形
  /// （[SshProxyOptions]）には解決済み credential が載っている前提で検証する。
  void _validateProxy(SshProxyOptions? proxy) {
    if (proxy == null) return;

    final hops = proxy.hops;
    if (hops.isEmpty) {
      throw SshConnectionError('Jump host chain must not be empty');
    }
    if (hops.length > maxProxyHops) {
      throw SshConnectionError(
        l10n()?.connProxyMaxHops(maxProxyHops) ??
            'Up to $maxProxyHops hops',
      );
    }

    final seen = <String>{};
    for (final hop in hops) {
      if (hop.host.trim().isEmpty) {
        throw SshConnectionError(
          l10n()?.sshHostRequired ?? 'Host is required',
        );
      }
      if (hop.port < 1 || hop.port > 65535) {
        throw SshConnectionError(
          l10n()?.sshInvalidPortNumber(hop.port) ??
              'Invalid port number: ${hop.port}',
        );
      }
      if (hop.username.trim().isEmpty) {
        throw SshConnectionError(
          l10n()?.sshUsernameRequired ?? 'Username is required',
        );
      }
      final hasCredential =
          (hop.password != null && hop.password!.isNotEmpty) ||
          (hop.privateKey != null && hop.privateKey!.isNotEmpty);
      if (!hasCredential) {
        throw SshAuthenticationError(
          l10n()?.sshCredentialRequired ??
              'Either password or privateKey must be provided',
        );
      }
      final key = '${hop.host.toLowerCase()}:${hop.port}';
      if (!seen.add(key)) {
        throw SshConnectionError(
          l10n()?.connProxyDuplicateHop(hop.host, hop.port) ??
              'Jump host ${hop.host}:${hop.port} is already in the chain',
        );
      }
    }

    // M6: forwardHost が非空のときだけ forwardPort を検証する
    //（forwardPort のみ入力は無視）。
    if (proxy.forwardHost.trim().isNotEmpty &&
        (proxy.forwardPort < 1 || proxy.forwardPort > 65535)) {
      throw SshConnectionError(
        l10n()?.sshInvalidPortNumber(proxy.forwardPort) ??
            'Invalid port number: ${proxy.forwardPort}',
      );
    }
  }

  /// SSH 接続を確立して接続資源を返す（HEAD `SshClient.connect` の接続部相当）。
  ///
  /// 戻り record は Issue #56 で `jumpClients` 付きへ拡張した。**
  /// `connectionFactory` の型契約は不変**（factory 経路は
  /// `jumpClients: const []`）。
  Future<({SSHSocket socket, SSHClient client, List<SSHClient> jumpClients})>
  connect({
    required String host,
    required int port,
    required String username,
    required SshConnectOptions options,
    required void Function() onAuthenticated,
  }) async {
    // 前回接続の移行保留をリセット（成功・失敗どちらでも次回に持ち越さない）
    _pendingFingerprintMigrations = null;

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
      // factory は jump を含まない（型契約不変・空で包む）
      return (
        socket: connection.socket,
        client: connection.client,
        jumpClients: const <SSHClient>[],
      );
    }

    final proxy = options.proxy;
    final SSHSocket socket;
    final List<SSHClient> jumpClients;
    if (proxy != null) {
      // ジャンプ経路: ソケット生成を tunneler へ委譲する
      final tunnel = await _tunneler.tunnel(
        proxy: proxy,
        options: options,
        onVerifyHostKey: (hop, type, fingerprint) => _onVerifyHostKey(
          hop.host,
          hop.port,
          type,
          fingerprint,
          acceptNewHostKeys: options.acceptNewHostKeys,
        ),
      );
      socket = tunnel.socket;
      jumpClients = tunnel.jumpClients;
    } else {
      // 直接経路: ソケット接続（現行経路）
      socket = await socketDialer(
        host,
        port,
        timeout: Duration(seconds: options.timeout),
      );
      jumpClients = const [];
    }

    try {
      final client = _buildClient(
        socket,
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
      return (socket: socket, client: client, jumpClients: jumpClients);
    } catch (e) {
      // C1: tunnel 後〜return の窓。失敗時は proxy 経路なら構築済み jump
      // を後ろから close、非 proxy 経路なら socket を close して rethrow
      // （既存の socket リーク欠陥も同窓のため一緒に塞ぐ）。
      for (final jump in jumpClients.reversed) {
        jump.close();
      }
      if (jumpClients.isEmpty) {
        socket.close();
      }
      rethrow;
    }
  }

  /// 認証方式に応じた target SSHClient を組立る（同期・鍵パース失敗は throw）。
  SSHClient _buildClient(
    SSHSocket socket,
    String username,
    SshConnectOptions options,
    void Function() onAuthenticated,
    Future<bool> Function(String type, Uint8List fingerprint) onVerifyHostKey,
  ) {
    if (options.privateKey != null) {
      // 鍵認証
      return SSHClient(
        socket,
        username: username,
        identities: _parsePrivateKey(options.privateKey!, options.passphrase),
        // inventory: SSH-LIFE-018
        onAuthenticated: onAuthenticated,
        onVerifyHostKey: onVerifyHostKey,
      );
    }
    if (options.password != null) {
      // パスワード認証
      return SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => options.password!,
        onAuthenticated: onAuthenticated,
        onVerifyHostKey: onVerifyHostKey,
      );
    }
    throw SshAuthenticationError('No authentication method provided');
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
      // jump + target の両方が保留になり得るため List に積む。
      if (acceptNewHostKeys) {
        final pending = _pendingFingerprintMigrations ??= [];
        pending.add(
          (host: host, port: port, type: type, fingerprint: formatted),
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
  /// （HEAD `SshClient.connect` 内の移行適用相当・保留は複数件あり得る）。
  Future<void> applyPendingMigrationOnAuthenticated() async {
    final pending = _pendingFingerprintMigrations;
    _pendingFingerprintMigrations = null;
    final storage = SecureStorageService();
    for (final item in pending ?? const <({String host, int port, String type, String fingerprint})>[]) {
      await storage.saveHostKeyFingerprint(
        item.host,
        item.port,
        item.type,
        item.fingerprint,
      );
    }
  }
}
