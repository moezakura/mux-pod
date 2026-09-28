import '../../l10n/app_localizations.dart' show AppLocalizations;
import '../../providers/connection_provider.dart' show Connection;
import '../../services/herdr/herdr_adapter.dart' show HerdrAdapter;
import '../../services/herdr/herdr_models.dart' show HerdrSnapshot;
import '../../services/keychain/secure_storage.dart' show SecureStorageService;
import '../../services/ssh/ssh_authentication_error.dart'
    show SshAuthenticationError;
import '../../services/ssh/ssh_client.dart' show SshClient;
import '../../services/ssh/ssh_models.dart' show SshConnectOptions;
import '../../services/ssh/ssh_proxy_options_resolver.dart'
    show SshProxyOptionsResolver;
import '../../services/tmux/ssh_tmux_command_executor.dart';
import '../../services/tmux/tmux_facade.dart' show tmuxFacade;
import '../../services/tmux/tmux_models.dart' show TmuxSession;

/// 接続カードのセッション/ワークスペース操作を担う協調オブジェクト。
///
/// SSH 接続・snapshot/listSessions の取得・kill/close/create の mutation を
/// プロトコルレベルで実行する。**ref には依存しない**（戻り値で結果を返し、
/// 呼出側の State 骨格が「mounted ガード → setState → updateSessionsFromDomain」
/// を行う）。l10n は「host・username 等の表示」ではなく、SSH 認証エラーの
/// 文言生成のために引数で受ける。
///
/// 各メソッドの戻り値は呼出側 State が保持する生データ（`List<TmuxSession>` /
/// `HerdrSnapshot`）と同じ形状で返す。domain 変換（`toDomain` /
/// `toDomainSessions`）と provider 同期は State 骨格が担う。
class ConnectionSessionOperations {
  /// 認証情報を取得して SSH 接続し、接続済みクライアントを返す。
  ///
  /// [factory] はテストからの注入用（提供されれば優先使用）。
  /// ジャンプホストは [SshProxyOptionsResolver] で解決する（MR-8 契約・
  /// 解決失敗は SshProxyConnectionError throw で呼出元へ伝播）。
  /// keepalive は「接続個別 > 全体設定」で解決する（🤝3）。本クラスは
  /// ref に依存しないため、全体設定値は呼出元が [globalKeepAliveTimeoutSeconds]
  /// で注入する（未注入時は接続個別のみ・null は transport 自動式）。
  Future<SshClient> connect({
    required Connection connection,
    Future<SshClient> Function(Connection connection)? factory,
    required AppLocalizations l10n,
    int? globalKeepAliveTimeoutSeconds,
  }) async {
    if (factory != null) return factory(connection);
    final storage = SecureStorageService();
    final proxyOptions = await const SshProxyOptionsResolver().resolve(
      connection.proxy,
      connectionId: connection.id,
      targetHost: connection.host,
      targetPort: connection.port,
      l10n: l10n,
    );
    final keepAliveTimeoutSeconds =
        connection.keepAliveTimeoutSeconds ?? globalKeepAliveTimeoutSeconds;
    SshConnectOptions options;
    if (connection.authMethod == 'key' && connection.keyId != null) {
      final privateKey = await storage.getPrivateKey(connection.keyId!);
      if (privateKey == null) {
        throw SshAuthenticationError(l10n.connPrivateKeyUnreadable);
      }
      final passphrase = await storage.getPassphrase(connection.keyId!);
      options = SshConnectOptions(
        privateKey: privateKey,
        passphrase: passphrase,
        multiplexer: connection.multiplexer,
        proxy: proxyOptions,
        keepAliveTimeoutSeconds: keepAliveTimeoutSeconds,
      );
    } else {
      final password = await storage.getPassword(connection.id);
      options = SshConnectOptions(
        password: password,
        multiplexer: connection.multiplexer,
        proxy: proxyOptions,
        keepAliveTimeoutSeconds: keepAliveTimeoutSeconds,
      );
    }
    final sshClient = SshClient();
    await sshClient.connect(
      host: connection.host,
      port: connection.port,
      username: connection.username,
      options: options,
      lightweight: true,
      l10n: l10n,
    );
    return sshClient;
  }

  /// tmux: セッション一覧（`list-sessions`）を取得する。
  Future<List<TmuxSession>> fetchTmuxSessions(SshClient client) async {
    return tmuxFacade.listSessions(client.tmuxExecutor);
  }

  /// herdr: 全階層スナップショットを取得する。
  Future<HerdrSnapshot> fetchHerdrSnapshot(SshClient client) async {
    return HerdrAdapter(client).snapshot();
  }

  /// tmux: `kill-session` を実行し、同一接続で一覧を再取得する。
  ///
  /// kill → reload の await 順序（同一接続性）は接続テストが固定している
  /// ため、`unawaited` にせずこの順序で逐次 await する。
  Future<List<TmuxSession>> killSessionAndReload(
    SshClient client,
    String sessionName,
  ) async {
    await tmuxFacade.killSession(client.tmuxExecutor, sessionName);
    return fetchTmuxSessions(client);
  }

  /// herdr: workspace を閉じ、閉鎖後の一覧をスナップショット再取得する。
  ///
  /// workspace 内の全 tab / pane が連鎖終了するため、確認ダイアログは
  /// 呼出側 State が表示する（このメソッドは close → snapshot の順序のみ）。
  Future<HerdrSnapshot> closeWorkspace(
    SshClient client,
    String workspaceId,
  ) async {
    final adapter = HerdrAdapter(client);
    await adapter.workspaceClose(workspaceId);
    return adapter.snapshot();
  }

  /// herdr: workspace を作成し、作成後の一覧をスナップショット再取得する。
  Future<HerdrSnapshot> createWorkspace(SshClient client, String label) async {
    final adapter = HerdrAdapter(client);
    await adapter.workspaceCreate(label: label);
    return adapter.snapshot();
  }
}
