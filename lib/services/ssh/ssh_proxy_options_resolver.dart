import '../../l10n/app_localizations.dart';
import '../connection/proxy_config.dart';
import '../keychain/secure_storage.dart';
import 'ssh_models.dart';
import 'ssh_proxy_connection_error.dart';

/// 保存済み接続のジャンプホスト設定（[ProxyConfig]）を runtime 形
/// （[SshProxyOptions]）へ解決する resolver（保存済み接続経路 ①②③ 用）。
///
/// MR-8 契約:
/// - `null` 返却は [proxy] == null（直接接続）の**み**。
/// - 解決失敗（パスワード未保存・鍵 unavailable）は hop 座標付き
///   [SshProxyConnectionError] を throw して fail-fast する
///   （部分的に解決された options は返さない）。
///
/// persisted 形の keyId をストレージで解決した平文認証情報のみを runtime 形
/// に載せる（transport 層にストレージ命名規約を漏らさない）。
/// 接続テスト（④ 経路）は resolver を通さずフォーム値から直接構築する
/// （MR-3・未保存の jump password でもテスト可能にするため）。
class SshProxyOptionsResolver {
  const SshProxyOptionsResolver();

  /// [proxy] を runtime 形へ解決する。
  ///
  /// [targetHost] / [targetPort] は接続先（`Connection.host` / `port`）の
  /// 座標で、転送先未指定時に [SshProxyOptions.forwardHost] /
  /// [forwardPort] を埋めるのに使う（M3: runtime 形の転送先は常に非 null）。
  ///
  /// 転送先の正規化（M6）: [ProxyConfig.forwardHost] の空文字は未指定扱い。
  /// forwardHost 未指定時に [ProxyConfig.forwardPort] のみの入力は無視して
  /// [targetPort] を使う（転送先ホストなしの転送先ポートは意味を持たない）。
  Future<SshProxyOptions?> resolve(
    ProxyConfig? proxy, {
    required String connectionId,
    required String targetHost,
    required int targetPort,
    required AppLocalizations l10n,
  }) async {
    if (proxy == null) return null;

    final storage = SecureStorageService();
    final resolvedHops = <SshProxyHop>[];
    for (var i = 0; i < proxy.hops.length; i++) {
      final hop = proxy.hops[i];
      if (hop.authMethod == 'key') {
        resolvedHops.add(await _resolveKeyHop(storage, hop, i, l10n));
      } else {
        resolvedHops.add(
          await _resolvePasswordHop(storage, hop, i, connectionId, l10n),
        );
      }
    }

    return SshProxyOptions(
      hops: resolvedHops,
      forwardHost: _resolvedForwardHost(proxy, targetHost),
      forwardPort: _resolvedForwardPort(proxy, targetPort),
    );
  }

  Future<SshProxyHop> _resolvePasswordHop(
    SecureStorageService storage,
    ProxyHop hop,
    int hopIndex,
    String connectionId,
    AppLocalizations l10n,
  ) async {
    final password = await storage.getProxyPassword(connectionId, hopIndex);
    if (password == null || password.isEmpty) {
      throw _hopError(l10n.connProxyCredentialMissing(hop.host), hopIndex, hop);
    }
    return SshProxyHop(
      host: hop.host,
      port: hop.port,
      username: hop.username,
      password: password,
    );
  }

  Future<SshProxyHop> _resolveKeyHop(
    SecureStorageService storage,
    ProxyHop hop,
    int hopIndex,
    AppLocalizations l10n,
  ) async {
    final keyId = hop.keyId;
    final privateKey = keyId == null || keyId.isEmpty
        ? null
        : await storage.getPrivateKey(keyId);
    if (privateKey == null) {
      throw _hopError(l10n.connProxyKeyMissing(hop.host), hopIndex, hop);
    }
    final passphrase = keyId == null
        ? null
        : await storage.getPassphrase(keyId);
    return SshProxyHop(
      host: hop.host,
      port: hop.port,
      username: hop.username,
      privateKey: privateKey,
      passphrase: passphrase,
    );
  }

  SshProxyConnectionError _hopError(
    String message,
    int hopIndex,
    ProxyHop hop,
  ) {
    return SshProxyConnectionError(message, null, hopIndex, hop.host, hop.port);
  }

  String _resolvedForwardHost(ProxyConfig proxy, String targetHost) {
    final explicit = proxy.forwardHost?.trim();
    if (explicit == null || explicit.isEmpty) {
      return targetHost;
    }
    return explicit;
  }

  int _resolvedForwardPort(ProxyConfig proxy, int targetPort) {
    final explicit = proxy.forwardHost?.trim();
    if (explicit == null || explicit.isEmpty) {
      // 転送先ホストが未指定なら forwardPort のみの入力は無視する（M6）。
      return targetPort;
    }
    return proxy.forwardPort ?? targetPort;
  }
}
