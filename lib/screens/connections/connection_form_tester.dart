import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/backend/backend_type.dart';
import '../../services/backend/multiplexer_config.dart';
import '../../services/command/command_request.dart';
import '../../services/herdr/herdr_adapter.dart';
import '../../services/herdr/herdr_commands.dart';
import '../../services/keychain/secure_storage.dart';
import '../../services/ssh/ssh_client.dart';
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
class ConnectionTester {
  const ConnectionTester();

  Future<ConnectionTestResult> run({
    required SshClient Function() sshClientFactory,
    required ConnectionFormValues values,
    required AppLocalizations l10n,
  }) async {
    String? errorMessage;
    bool tmuxInstalled = false;
    String? tmuxWarning;
    bool herdrReady = false;
    String? herdrWarning;

    SshClient? sshClient;

    try {
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
}
