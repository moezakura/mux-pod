import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/backend/backend_type.dart';
import '../../services/backend/multiplexer_config.dart';
import '../../services/command/command_request.dart';
import '../../services/connection/proxy_config.dart' show ProxyConfig;
import '../../services/herdr/herdr_adapter.dart';
import '../../services/herdr/herdr_commands.dart';
import '../../services/keychain/secure_storage.dart';
import '../../services/ssh/ssh_client.dart';
import '../../services/ssh/ssh_proxy_connection_error.dart';
import '../../services/tmux/commands/session_commands.dart';
import '../../services/tmux/ssh_tmux_command_executor.dart';
import '../../services/tmux/tmux_version.dart';
import 'connection_form_values.dart';

/// [ConnectionFormScreen] の接続テストで使用する [SshClient] のファクトリ。
///
/// テスト時に fake client を差し込めるよう Provider として公開する。
/// 定義は本ファイルへ移設し、元ファイル（connection_form_screen.dart）から
/// re-export して同一パスから供給する。
final connectionFormSshClientFactoryProvider = Provider<SshClient Function()>(
  (ref) => createSshClient,
);

/// 接続テストの結果。
class ConnectionTestResult {
  const ConnectionTestResult({
    this.errorMessage,
    this.tmuxInstalled = false,
    this.tmuxWarning,
    this.herdrReady = false,
    this.herdrWarning,
  });

  /// 致命的エラー（認証失敗・接続失敗・その他例外）の表示文言。
  /// null でない場合、成功/警告判定は行わない。
  final String? errorMessage;

  /// tmux 検出結果（[errorMessage] が null の場合のみ意味を持つ）。
  final bool tmuxInstalled;
  final String? tmuxWarning;

  /// herdr preflight 結果（[errorMessage] が null の場合のみ意味を持つ）。
  final bool herdrReady;
  final String? herdrWarning;
}

/// SSH 接続テストの実行（認証情報準備・connect・herdr preflight /
/// tmux バージョン検出・エラー分類・文言組み立て）。
///
/// Riverpod には依存しない。[SshClient] ファクトリ・入力値・l10n は
/// 呼出元（[ConnectionFormScreen] の State）から注入される。
///
/// ジャンプホストは resolver を通さずフォーム値から直接 [SshProxyOptions]
/// を構築する（MR-3: 保存前の jump password でもテスト可能にするため）。
/// テストは jump チェーン全体を検証する（🤝4: jump 不通ならテスト失敗）。
class ConnectionTester {
  const ConnectionTester();

  Future<ConnectionTestResult> run({
    required SshClient Function() sshClientFactory,
    required ConnectionFormValues values,
    required AppLocalizations l10n,

    /// 編集対象の接続 ID（新規作成時は null）。
    ///
    /// hop パスワードが空欄のとき保存済みキーへフォールバックする
    /// （編集時に再入力不要にするため）。
    String? connectionId,

    /// keepalive 全体設定（接続個別のフォーム値が空欄のときのフォールバック）。
    int? globalKeepAliveTimeoutSeconds,
  }) async {
    String? errorMessage;
    bool tmuxInstalled = false;
    String? tmuxWarning;
    bool herdrReady = false;
    String? herdrWarning;

    SshClient? sshClient;

    try {
      // ジャンプホスト経由設定をフォーム値＋target 座標から直接構築する
      // （MR-3: resolver バイパス・保存前 jump password でテスト可）。
      final proxy = await _buildProxyOptions(
        values,
        l10n: l10n,
        connectionId: connectionId,
      );

      // 認証情報を準備
      String? password;
      String? privateKey;
      String? passphrase;

      if (values.authMethod == 'password') {
        password = values.password;
        if (password.isEmpty) {
          throw SshAuthenticationError(l10n.connPasswordRequiredForTest);
        }
      } else if (values.authMethod == 'key') {
        if (values.keyId == null) {
          throw SshAuthenticationError(l10n.connKeyRequiredForTest);
        }
        final storage = SecureStorageService();
        privateKey = await storage.getPrivateKey(values.keyId!);
        passphrase = await storage.getPassphrase(values.keyId!);
        if (privateKey == null) {
          throw SshAuthenticationError(l10n.connPrivateKeyUnreadable);
        }
      }

      // SSH接続テスト
      final customPath = values.executablePath;
      final isHerdr = values.backend == BackendType.herdr;
      sshClient = sshClientFactory();
      await sshClient.connect(
        host: values.host,
        port: values.port,
        username: values.username,
        options: SshConnectOptions(
          password: password,
          privateKey: privateKey,
          passphrase: passphrase,
          multiplexer: isHerdr
              ? MultiplexerConfig(
                  backend: BackendType.herdr,
                  executablePath: customPath,
                )
              : MultiplexerConfig.tmux(customPath),
          proxy: proxy,
          keepAliveTimeoutSeconds:
              values.keepAliveTimeoutSecondsOrNull ??
              globalKeepAliveTimeoutSeconds,
        ),
        l10n: l10n,
      );

      if (isHerdr) {
        // Herdr preflight: `herdr status --json` で protocol（最小 17）を確認
        try {
          final adapter = HerdrAdapter(sshClient);
          await adapter.preflight();
          herdrReady = true;
        } on HerdrProtocolMismatchException catch (e) {
          herdrReady = false;
          herdrWarning = l10n.connHerdrProtocolMismatch(
            '${e.actual}',
            '${e.supported}',
          );
        } on HerdrCommandException catch (_) {
          herdrReady = false;
          herdrWarning = customPath != null
              ? l10n.connHerdrPathNotFound(customPath)
              : l10n.connHerdrNotFound;
        } catch (e) {
          herdrReady = false;
          herdrWarning = l10n.connHerdrCheckFailed('$e');
        }
      } else {
        // SSH接続後に tmux の実体を検出（version 取得ができれば利用可能）
        try {
          final result = await sshClient.tmuxExecutor.execute(
            CommandRequest(
              command: TmuxSessionCommands.version(),
              transport: CommandTransportPreference.ephemeralOnly,
              output: CommandOutputRequirement.separatedOutput,
            ),
          );
          if (result.exitCode != null && result.exitCode != 0) {
            tmuxInstalled = false;
            tmuxWarning = customPath != null
                ? l10n.connTmuxPathNotFound(customPath)
                : l10n.connTmuxNotFound;
          } else {
            final version = TmuxVersionInfo.parse(result.stdout);
            if (version != null) {
              tmuxInstalled = true;
            } else {
              tmuxInstalled = false;
              tmuxWarning = l10n.connTmuxVersionUnrecognized;
            }
          }
        } on SshConnectionError catch (_) {
          tmuxInstalled = false;
          tmuxWarning = customPath != null
              ? l10n.connTmuxPathNotFound(customPath)
              : l10n.connTmuxNotFound;
        } catch (e) {
          tmuxInstalled = false;
          tmuxWarning = l10n.connTmuxCheckFailed('$e');
        }
      }
    } on SshProxyConnectionError catch (e) {
      // hop 座標付きメッセージ（l10n 済み）をそのまま表示する。
      errorMessage = e.message;
    } on SshAuthenticationError catch (e) {
      errorMessage = l10n.connTestAuthFailed(e.message);
    } on SshConnectionError catch (e) {
      errorMessage = l10n.connTestConnectionFailed(e.message);
    } catch (e) {
      errorMessage = l10n.connTestError('$e');
    } finally {
      await sshClient?.dispose();
    }

    return ConnectionTestResult(
      errorMessage: errorMessage,
      tmuxInstalled: tmuxInstalled,
      tmuxWarning: tmuxWarning,
      herdrReady: herdrReady,
      herdrWarning: herdrWarning,
    );
  }

  /// フォーム値から [SshProxyOptions] を直接構築する（MR-3・resolver バイパス）。
  ///
  /// - hop パスワードはフォーム入力を優先し、空欄なら保存済みキーへ
  ///   フォールバック（編集時の再入力不要）。どちらもなければ
  ///   [connProxyPasswordRequiredForTest] で fail-fast。
  /// - hop の鍵は既存キー機構から解決し、unavailable なら
  ///   [connProxyKeyMissing] で fail-fast。
  /// - 転送先は [values.buildProxy] 済みの形（M6 正規化済み）を使い、
  ///   未指定なら target 座標で埋める（M3）。
  Future<SshProxyOptions?> _buildProxyOptions(
    ConnectionFormValues values, {
    required AppLocalizations l10n,
    required String? connectionId,
  }) async {
    final ProxyConfig? proxy = values.buildProxy();
    if (proxy == null) return null;

    final storage = SecureStorageService();
    final hops = <SshProxyHop>[];
    for (var i = 0; i < proxy.hops.length; i++) {
      final hop = proxy.hops[i];
      if (hop.authMethod == 'key') {
        final keyId = hop.keyId;
        final privateKey = keyId == null || keyId.isEmpty
            ? null
            : await storage.getPrivateKey(keyId);
        if (privateKey == null) {
          throw SshProxyConnectionError(
            l10n.connProxyKeyMissing(hop.host),
            null,
            i,
            hop.host,
            hop.port,
          );
        }
        final passphrase = keyId == null
            ? null
            : await storage.getPassphrase(keyId);
        hops.add(
          SshProxyHop(
            host: hop.host,
            port: hop.port,
            username: hop.username,
            privateKey: privateKey,
            passphrase: passphrase,
          ),
        );
      } else {
        var password =
            i < values.proxyHops.length
            ? values.proxyHops[i].passwordText
            : '';
        if (password.isEmpty && connectionId != null) {
          password = await storage.getProxyPassword(connectionId, i) ?? '';
        }
        if (password.isEmpty) {
          throw SshProxyConnectionError(
            l10n.connProxyPasswordRequiredForTest,
            null,
            i,
            hop.host,
            hop.port,
          );
        }
        hops.add(
          SshProxyHop(
            host: hop.host,
            port: hop.port,
            username: hop.username,
            password: password,
          ),
        );
      }
    }

    return SshProxyOptions(
      hops: hops,
      forwardHost: proxy.forwardHost ?? values.host,
      forwardPort: proxy.forwardPort ?? values.port,
    );
  }
}
