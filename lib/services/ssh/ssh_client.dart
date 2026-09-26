import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import '../command/command_request.dart';
import '../command/command_result.dart';
import '../connection_error.dart';
import '../tmux/tmux_backend.dart';
import 'persistent_shell.dart';
import 'ssh_authentication_error.dart';
import 'ssh_command_executor.dart';
import 'ssh_connection_state.dart';
import 'ssh_connection_state_controller.dart';
import 'ssh_connector.dart';
import 'ssh_event_broker.dart';
import 'ssh_interactive_shell.dart';
import 'ssh_keep_alive.dart';
import 'ssh_managed_pty.dart';
import 'ssh_models.dart';
import 'ssh_proxy_connection_error.dart';
import 'ssh_proxy_tunneler.dart';
import 'ssh_resource_manager.dart';
import 'ssh_sftp.dart';
import 'ssh_shell_manager.dart';

export '../connection_error.dart';
export 'ssh_authentication_error.dart';
export 'ssh_connection_state.dart';
export 'ssh_factory.dart';
export 'ssh_managed_pty.dart';
export 'ssh_models.dart';

// inventory: SSH-019
/// SSHクライアント
///
/// dartssh2をラップし、SSH接続を管理する。
///
/// [BackendAdapter]（互換名 [TmuxBackend]）を実装し、backend 層は
/// 具象型ではなく抽象にだけ依存する。
///
/// composition root：公開 API（BackendAdapter 面）を所有者/コラボレータへ
/// 委譲する配線のみを持つ。状態・イベント・資源はそれぞれ
/// [SshConnectionStateController] / [SshEventBroker] / [SshResourceManager] が
/// 単一所有し、コラボレータ間はこのクラスが配線したクロージャのみで結合する
/// （相互参照なし・依存は一方向）。
class SshClient implements BackendAdapter {
  final Future<({SSHSocket socket, SSHClient client})> Function(
    String host,
    int port,
    String username,
    SshConnectOptions options,
    void Function() onAuthenticated,
    Future<bool> Function(String type, Uint8List fingerprint) onVerifyHostKey,
  )?
  _connectionFactory;
  final Future<PersistentShell?> Function(SSHClient client)?
  _persistentShellFactory;
  final Timer Function(Duration duration, void Function() callback)
  _timerFactory;

  /// ローカライズ文字列（[connect] の [l10n] 引数で設定。null 時は英語フォールバック）。
  ///
  /// 全コラボレータへは `l10n` クロージャ（`() => _l10n`）で注入するため、
  /// connect() で更新するだけで全コラボレータのエラー文言が追随する。
  AppLocalizations? _l10n;

  /// 接続時に使用したオプション
  // inventory: SSH-020
  SshConnectOptions? _connectOptions;

  /// 接続状態の単一所有者。
  late final SshConnectionStateController _stateController;

  /// イベント配信の単一所有者。
  late final SshEventBroker _eventBroker;

  /// 資源ライフサイクルの単一所有者。
  late final SshResourceManager _resourceManager;

  /// 接続確立の執行者。
  late final SshConnector _connector;

  /// 持続的シェル2本の生成・再起動。
  late final SshShellManager _shellManager;

  /// コマンド実行（_execLock 所有者）。
  late final SshCommandExecutor _executor;

  /// Keep-alive（カウンタ所有者）。
  late final SshKeepAlive _keepAlive;

  /// インタラクティブシェル。
  late final SshInteractiveShell _interactiveShell;

  /// SFTP キャッシュ管理。
  late final SshSftpAccess _sftp;

  /// 入力シェルが再起動した際に呼ばれるコールバック。
  /// Tmux 側が restore trap を再設定するために使用する。
  void Function()? onInputShellRebooted;

  SshClient({
    Future<({SSHSocket socket, SSHClient client})> Function(
      String host,
      int port,
      String username,
      SshConnectOptions options,
      void Function() onAuthenticated,
      Future<bool> Function(String type, Uint8List fingerprint) onVerifyHostKey,
    )?
    connectionFactory,
    Future<PersistentShell?> Function(SSHClient client)? persistentShellFactory,
    Timer Function(Duration duration, void Function() callback)? timerFactory,
    SshProxyTunneler? proxyTunneler,
  }) : _connectionFactory = connectionFactory,
       _persistentShellFactory = persistentShellFactory,
       _timerFactory = timerFactory ?? Timer.new {
    _stateController = SshConnectionStateController();
    _eventBroker = SshEventBroker();
    _resourceManager = SshResourceManager();
    _connector = SshConnector(
      connectionFactory: _connectionFactory,
      l10n: () => _l10n,
      setLastError: _setLastError,
      tunneler: proxyTunneler,
    );
    _shellManager = SshShellManager(
      client: () => _resourceManager.client,
      isConnected: () => isConnected,
      pollingShell: () => _resourceManager.persistentShell,
      inputShell: () => _resourceManager.inputShell,
      persistentShellFactory: _persistentShellFactory,
      l10n: () => _l10n,
      attachPollingShell: _resourceManager.attachPollingShell,
      attachInputShell: _resourceManager.attachInputShell,
      onInputShellRebooted: () => onInputShellRebooted,
    );
    _executor = SshCommandExecutor(
      l10n: () => _l10n,
      isConnected: () => isConnected,
      client: () => _resourceManager.client,
      pollingShell: () => _resourceManager.persistentShell,
      restartPollingShell: () => _shellManager.restartPolling(),
    );
    _keepAlive = SshKeepAlive(
      timerFactory: _timerFactory,
      probe: () => _executor.execute(
        // 🤝3: probe タイムアウトは接続時に解決されたインスタンス値を参照する
        // （未接続・未設定時の既定は 10 秒 = 従来の static const と同一）。
        CommandRequest(
          command: 'echo ping',
          transport: CommandTransportPreference.persistentPreferred,
          output: CommandOutputRequirement.outputOnly,
          timeout: Duration(seconds: _keepAlive.keepAliveProbeTimeoutSeconds),
        ),
      ),
      onDead: _onKeepAliveDead,
      isConnected: () => isConnected,
      client: () => _resourceManager.client,
      l10n: () => _l10n,
    );
    _interactiveShell = SshInteractiveShell(
      l10n: () => _l10n,
      isConnected: () => isConnected,
      client: () => _resourceManager.client,
      session: () => _resourceManager.session,
      attachSession: _resourceManager.attachSession,
      setLastError: _setLastError,
      onData: _eventBroker.onData,
      onError: _eventBroker.onError,
      onDone: _onShellDone,
    );
    _sftp = SshSftpAccess(
      l10n: () => _l10n,
      isConnected: () => isConnected,
      client: () => _resourceManager.client,
      cachedSftp: () => _resourceManager.cachedSftp,
      setCachedSftp: _resourceManager.attachCachedSftp,
    );
  }

  /// lastError の書込（コラボレータへ注入するクロージャの実体）。
  void _setLastError(String? value) => _stateController.lastError = value;

  /// keep-alive 失敗閾値到達時の状態遷移・イベント発火
  /// （HEAD `_sendKeepAlive` の最終分岐相当）。
  void _onKeepAliveDead(String message) {
    _stateController.lastError = message;
    _stateController.transition(SshConnectionState.error);
    _eventBroker.onError(SshConnectionError(message));
    _eventBroker.onClose();
  }

  /// インタラクティブシェル完了時の状態遷移・イベント発火
  /// （HEAD `_handleDone` 相当。ストリーム発行はしない）。
  void _onShellDone() {
    _stateController.setState(SshConnectionState.disconnected);
    _eventBroker.onClose();
  }

  // inventory: LEGACY-0138
  /// 接続時に使用したオプション
  SshConnectOptions? get connectOptions => _connectOptions;

  /// ユーザーが接続設定で指定した実行ファイルパス。
  @override
  // inventory: SSH-NEW-001
  String? get userExecutablePath =>
      _connectOptions?.multiplexer?.executablePath;

  /// 入力専用の持続的シェル
  @override
  // inventory: LEGACY-0140
  TmuxInputTransport? get inputTransport => _resourceManager.inputShell;

  /// 入力専用シェルを再起動する。
  @override
  // inventory: LEGACY-0141
  Future<void> restartInputTransport() => restartInputShell();

  /// 入力シェルが再起動した際に呼ばれるコールバック。
  /// Tmux 側が restore trap を再設定するために使用する。
  @override
  // inventory: LEGACY-0142
  void Function()? get onInputTransportRebooted => onInputShellRebooted;

  @override
  set onInputTransportRebooted(void Function()? value) {
    onInputShellRebooted = value;
  }

  // inventory: LEGACY-0143
  /// ポーリング用の持続的シェル
  PersistentShell? get persistentShell => _resourceManager.persistentShell;

  // inventory: LEGACY-0144
  /// 入力専用の持続的シェル
  PersistentShell? get inputShell => _resourceManager.inputShell;

  /// 接続状態のストリーム（外部から監視用）
  // inventory: SSH-024
  // inventory: LEGACY-0145
  Stream<SshConnectionState> get connectionStateStream =>
      _stateController.connectionStateStream;

  // inventory: SSH-021
  // inventory: LEGACY-0146
  /// 現在の接続状態
  SshConnectionState get state => _stateController.state;

  /// 接続中かどうか
  // inventory: SSH-022
  @override
  // inventory: LEGACY-0147
  bool get isConnected => state == SshConnectionState.connected;

  // inventory: SSH-023
  // inventory: LEGACY-0148
  /// 最後のエラーメッセージ
  String? get lastError => _stateController.lastError;

  /// 接続時に解決された keepalive probe タイムアウト（秒・🤝3）。
  ///
  /// probe クロージャが CommandRequest の timeout に使う現在値
  ///（テスト観察用の公開ゲッター）。未接続時は既定値 10。
  int get keepAliveProbeTimeoutSeconds =>
      _keepAlive.keepAliveProbeTimeoutSeconds;

  // inventory: SSH-025
  // inventory: LEGACY-0149
  /// SFTPクライアントを取得（キャッシュ付き・詳細は [SshSftpAccess.openSftp]）。
  Future<SftpClient> openSftp() => _sftp.openSftp();

  // inventory: SSH-026
  // inventory: LEGACY-0150
  /// SSH接続を確立する。接続部は [SshConnector]、資源登録は
  /// [SshResourceManager] へ委譲する。
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required SshConnectOptions options,
    bool lightweight = false,
    AppLocalizations? l10n,
  }) async {
    // ローカライズ文字列を保持（null 時は英語フォールバック・テスト互換）。
    _l10n = l10n;

    // バリデーション
    // inventory: SSH-LIFE-016
    _connector.validateConnectionParams(host, port, username, options);

    _stateController.setState(SshConnectionState.connecting);
    _stateController.lastError = null;

    try {
      final connection = await _connector.connect(
        host: host,
        port: port,
        username: username,
        options: options,
        onAuthenticated: _onAuthenticated,
      );
      _resourceManager.attachConnection(
        socket: connection.socket,
        client: connection.client,
      );
      // M5: jump clients も attachConnection と同一位置（認証待ちの前）で登録。
      // これにより target 認証失敗時も _cleanup → disposeAll が jump を閉じられる。
      _resourceManager.attachJumpClients(connection.jumpClients);

      // 🤝3: keepalive 開始前に probe タイムアウトを解決して適用する
      //（options.keepAliveTimeoutSeconds は UI が「接続個別 > 全体設定」を
      // 解決した上書き値。null の場合は自動式（proxy あり: 10 + hops × 5 /
      // なし: 10））。直接接続・未設定時は 10 秒のまま = 既存挙動完全不変。
      _keepAlive.keepAliveProbeTimeoutSeconds =
          SshKeepAlive.resolveKeepAliveTimeoutSeconds(
        perConnection: options.keepAliveTimeoutSeconds,
        proxy: options.proxy,
      );

      // 認証完了を待機
      await _resourceManager.client!.authenticated;

      // 旧形式保存値からの移行: 認証が成功した場合のみ正規形式で保存する
      // （認証失敗時は更新しない = 問題なければ SHA256 に Update）。
      await _connector.applyPendingMigrationOnAuthenticated();

      _stateController.setState(SshConnectionState.connected);
      _stateController.emit();

      // 接続オプションを保存（backend 側は userExecutablePath 経由で取得）
      _connectOptions = options;

      // 一括コマンド実行用の軽量接続では、ポーリング用シェルとkeep-aliveをスキップ。
      // execWithExitCode は専用チャネルを使うため持続的シェルは不要。
      if (!lightweight) {
        // 持続的シェルを開始（ポーリング用）
        // inventory: SSH-LIFE-001
        await _shellManager.startShells();
        // Keep-aliveを開始
        // inventory: SSH-LIFE-008
        _keepAlive.start();
      }
    } on SshProxyConnectionError catch (e) {
      // ジャンプ経路エラーは hop 座標付き・l10n 済みメッセージをそのまま
      // 表示する（wrap 前メッセージを lastError へ・hop 座標を失わせない）。
      _stateController.setState(SshConnectionState.error);
      _stateController.lastError = e.message;
      await _cleanup();
      rethrow;
    } on SocketException catch (e) {
      _stateController.setState(SshConnectionState.error);
      _stateController.lastError =
          _l10n?.connTestConnectionFailed(e.message) ??
          'Connection failed: ${e.message}';
      // inventory: SSH-LIFE-020
      await _cleanup();
      throw SshConnectionError(_stateController.lastError!, e);
    } on SSHAuthFailError catch (e) {
      _stateController.setState(SshConnectionState.error);
      _stateController.lastError =
          _l10n?.connTestAuthFailed(e.message) ??
          'Authentication failed: ${e.message}';
      await _cleanup();
      throw SshAuthenticationError(_stateController.lastError!, e);
    } catch (e) {
      _stateController.setState(SshConnectionState.error);
      _stateController.lastError =
          _l10n?.connTestConnectionFailed(e.toString()) ??
          'Connection failed: $e';
      await _cleanup();
      throw SshConnectionError(_stateController.lastError!, e);
    }
  }

  /// 認証完了コールバック
  void _onAuthenticated() {
    // 認証成功
  }

  // inventory: SSH-027
  // inventory: LEGACY-0151
  /// 接続を切断する
  Future<void> disconnect() async {
    await _cleanup();
    // inventory: SSH-LIFE-019
    _stateController.transition(SshConnectionState.disconnected);
    _eventBroker.onClose();
  }

  /// リソースをクリーンアップ（keep-alive 停止 + 資源解放）
  Future<void> _cleanup() async {
    // Keep-aliveを停止
    // inventory: SSH-LIFE-010
    _keepAlive.stop();
    await _resourceManager.disposeAll();
  }

  // inventory: SSH-028
  // inventory: LEGACY-0152
  /// 持続的シェルを再起動
  Future<void> restartPersistentShell() => _shellManager.restartPolling();

  // inventory: SSH-LIFE-003
  // inventory: LEGACY-0153
  /// 入力専用シェルを再起動する（送信失敗時の自己回復用）。
  Future<void> restartInputShell() => _shellManager.restartInput();

  // tmux 固有のキー送信・restore trap ・復元は Tmux 側の SshTmuxCommandExecutor で担う。

  // inventory: SSH-037
  // inventory: LEGACY-0154
  /// インタラクティブシェルを開始する
  ///
  /// [options] シェルオプション
  Future<void> startShell([ShellOptions options = const ShellOptions()]) =>
      _interactiveShell.startShell(options);

  /// シェルにデータを書き込む
  ///
  /// [data] 送信データ（文字列）
  // inventory: SSH-038
  @override
  // inventory: LEGACY-0155
  void write(String data) => _interactiveShell.write(data);

  // inventory: SSH-039
  // inventory: LEGACY-0156
  /// シェルにバイトデータを書き込む
  ///
  /// [data] 送信データ（バイト）
  void writeBytes(Uint8List data) => _interactiveShell.writeBytes(data);

  // inventory: SSH-040
  // inventory: LEGACY-0157
  /// ターミナルサイズを変更する
  ///
  /// [cols] カラム数
  /// [rows] 行数
  void resize(int cols, int rows) => _interactiveShell.resize(cols, rows);

  /// 汎用コマンド実行（[CommandExecutor] 実装・詳細は [SshCommandExecutor.execute]）。
  @override
  Future<CommandResult> execute(CommandRequest request) =>
      _executor.execute(request);

  // inventory: SSH-035
  // inventory: LEGACY-0160
  /// イベントハンドラを設定する
  void setEventHandlers(SshEvents events) =>
      _eventBroker.setEventHandlers(events);

  // inventory: SSH-036
  // inventory: LEGACY-0161
  /// イベントハンドラを更新する
  void updateEventHandlers({
    void Function(Uint8List data)? onData,
    void Function()? onClose,
    void Function(Object error)? onError,
  }) {
    _eventBroker.updateEventHandlers(
      onData: onData,
      onClose: onClose,
      onError: onError,
    );
  }

  // inventory: SSH-041
  // inventory: LEGACY-0162
  /// リソースを解放する
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
  }

  // inventory: SSH-042
  /// PTY 付きで [command] を起動し、ライフサイクルを管理する managed process を
  /// 開始する（hidden herdr TUI ホスト用）。二重 start は既存 managed session を
  /// close してから起動する（リーク防止）。
  Future<ManagedPtyProcess> startManagedPty(
    String command, {
    required int cols,
    required int rows,
  }) async {
    if (!isConnected || _resourceManager.client == null) {
      throw SshConnectionError(_l10n?.sshNotConnected ?? 'Not connected');
    }
    // 二重 start: 既存 managed session を close（channel リーク防止）。
    final previous = _resourceManager.takeManagedPty();
    if (previous != null) {
      await previous.close();
    }
    final session = await _resourceManager.client!.execute(
      command,
      pty: SSHPtyConfig(type: 'xterm-256color', width: cols, height: rows),
    );
    final process = ManagedPtyProcess(session);
    _resourceManager.attachManagedPty(process);
    return process;
  }
}
