import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:dartssh2/dartssh2.dart';

import '../backend/multiplexer_config.dart';
import '../command/command_executor.dart';
import '../command/command_request.dart';
import '../command/command_result.dart';
import '../connection_error.dart';
import '../keychain/secure_storage.dart';
import '../tmux/tmux_backend.dart';
import 'persistent_shell.dart';
import 'ssh_authentication_error.dart';
import 'ssh_connection_state.dart';
export '../connection_error.dart';
export 'ssh_authentication_error.dart';
export 'ssh_connection_state.dart';

// inventory: SSH-003
/// SSH接続オプション
class SshConnectOptions {
  // inventory: SSH-004
  // inventory: LEGACY-0128
  /// パスワード認証時のパスワード
  final String? password;

  // inventory: SSH-005
  // inventory: LEGACY-0129
  /// 鍵認証時の秘密鍵（PEM形式）
  final String? privateKey;

  // inventory: SSH-006
  // inventory: LEGACY-0130
  /// 秘密鍵のパスフレーズ
  final String? passphrase;

  // inventory: SSH-007
  /// マルチプレクサ設定（nullなら自動検出）
  final MultiplexerConfig? multiplexer;

  // inventory: SSH-008
  // inventory: LEGACY-0132
  /// 接続タイムアウト（秒）
  final int timeout;

  // inventory: SSH-043
  /// 未知のホスト鍵を自動受け入れする（TOFU）。
  /// false の場合、未保存ホストは拒否する。
  final bool acceptNewHostKeys;

  SshConnectOptions({
    this.password,
    this.privateKey,
    this.passphrase,
    this.multiplexer,
    this.timeout = 30,
    this.acceptNewHostKeys = true,
  });
}

// inventory: SSH-009
/// シェルオプション
class ShellOptions {
  // inventory: SSH-010
  // inventory: LEGACY-0133
  /// ターミナルタイプ
  final String term;

  // inventory: SSH-011
  // inventory: LEGACY-0134
  /// カラム数
  final int cols;

  // inventory: SSH-012
  // inventory: LEGACY-0135
  /// 行数
  final int rows;

  const ShellOptions({
    this.term = 'xterm-256color',
    this.cols = 80,
    this.rows = 24,
  });
}

// inventory: SSH-013
/// SSH接続イベント
class SshEvents {
  // inventory: SSH-014
  // inventory: LEGACY-0136
  /// データ受信時
  final void Function(Uint8List data)? onData;

  // inventory: SSH-015
  /// 接続クローズ時
  final void Function()? onClose;

  // inventory: SSH-016
  /// エラー発生時
  final void Function(Object error)? onError;

  const SshEvents({this.onData, this.onClose, this.onError});

  // inventory: SSH-017
  // inventory: LEGACY-0137
  SshEvents copyWith({
    void Function(Uint8List data)? onData,
    void Function()? onClose,
    void Function(Object error)? onError,
  }) {
    return SshEvents(
      onData: onData ?? this.onData,
      onClose: onClose ?? this.onClose,
      onError: onError ?? this.onError,
    );
  }
}

// inventory: SSH-019
/// SSHクライアント
///
/// dartssh2をラップし、SSH接続を管理する。
///
/// [BackendAdapter]（互換名 [TmuxBackend]）を実装し、backend 層は
/// 具象型ではなく抽象にだけ依存する。
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
  }) : _connectionFactory = connectionFactory,
       _persistentShellFactory = persistentShellFactory,
       _timerFactory = timerFactory ?? Timer.new;

  SSHClient? _client;
  SSHSession? _session;
  SSHSocket? _socket;
  SftpClient? _cachedSftp;

  /// hidden herdr TUI ホスト用の managed PTY process（[startManagedPty] で起動）。
  ///
  /// [dispose] / 切断時に必ず close する（承認条件 9: bridge reset に加えて
  /// この cleanup でも hidden session を終了させる）。
  ManagedPtyProcess? _managedPty;

  SshConnectionState _state = SshConnectionState.disconnected;
  SshEvents _events = const SshEvents();
  String? _lastError;

  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;

  /// 持続的シェルセッション（ポーリング用）
  PersistentShell? _persistentShell;

  /// 入力専用の持続的シェル（キー送信の fire-and-forget 用）
  ///
  /// ポーリング用シェルとは別チャネルにすることで、キー入力がポーリングと
  /// 競合せず、チャネル開閉・execロック・往復待ちなしで即座に送信できる。
  PersistentShell? _inputShell;

  /// execチャネル排他制御用ロック
  Completer<void>? _execLock;

  /// 接続時に使用したオプション
  // inventory: SSH-020
  SshConnectOptions? _connectOptions;

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
  TmuxInputTransport? get inputTransport => _inputShell;

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

  void Function()? onInputShellRebooted;

  // inventory: LEGACY-0143
  /// ポーリング用の持続的シェル
  PersistentShell? get persistentShell => _persistentShell;

  // inventory: LEGACY-0144
  /// 入力専用の持続的シェル
  PersistentShell? get inputShell => _inputShell;

  /// Keep-aliveタイマー
  Timer? _keepAliveTimer;

  /// 接続監視用のStreamController
  final _connectionStateController =
      StreamController<SshConnectionState>.broadcast();

  /// 接続状態のストリーム（外部から監視用）
  // inventory: SSH-024
  // inventory: LEGACY-0145
  Stream<SshConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Keep-alive最小間隔（秒）
  static const int _minKeepAliveIntervalSeconds = 5;

  /// Keep-alive最大間隔（秒）
  static const int _maxKeepAliveIntervalSeconds = 30;

  /// Keep-aliveタイムアウト（秒）- 高速検知のため3秒に短縮
  static const int _keepAliveTimeoutSeconds = 3;

  /// 現在のKeep-alive間隔（動的に調整）
  int _currentKeepAliveIntervalSeconds = 10;

  /// Keep-alive連続成功回数
  int _keepAliveSuccessCount = 0;

  // inventory: SSH-021
  // inventory: LEGACY-0146
  /// 現在の接続状態
  SshConnectionState get state => _state;

  /// 接続中かどうか
  // inventory: SSH-022
  @override
  // inventory: LEGACY-0147
  bool get isConnected => _state == SshConnectionState.connected;

  // inventory: SSH-023
  // inventory: LEGACY-0148
  /// 最後のエラーメッセージ
  String? get lastError => _lastError;

  // inventory: SSH-025
  // inventory: LEGACY-0149
  /// SFTPクライアントを取得（キャッシュ付き）
  ///
  /// 初回呼び出し時にSFTPセッションを開始し、以降はキャッシュを返す。
  /// dartssh2の SftpClient.close() はSSHチャネルを解放しないため、
  /// SSH接続のライフサイクルで1つのSftpClientを使い回す。
  /// 呼び出し側で close() を呼んではならない。
  Future<SftpClient> openSftp() async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('SFTP requires an active SSH connection');
    }
    if (_cachedSftp != null) {
      debugPrint('[SshClient] openSftp: returning cached SftpClient');
      return _cachedSftp!;
    }
    debugPrint('[SshClient] openSftp: creating new SftpClient');
    _cachedSftp = await _client!.sftp();
    return _cachedSftp!;
  }

  // inventory: SSH-026
  // inventory: LEGACY-0150
  /// SSH接続を確立する
  ///
  /// [host] ホスト名またはIPアドレス
  /// [port] ポート番号
  /// [username] ユーザー名
  /// [options] 接続オプション（認証情報など）
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required SshConnectOptions options,
    bool lightweight = false,
  }) async {
    // バリデーション
    // inventory: SSH-LIFE-016
    _validateConnectionParams(host, port, username, options);

    _state = SshConnectionState.connecting;
    _lastError = null;

    try {
      final connectionFactory = _connectionFactory;
      if (connectionFactory != null) {
        final connection = await connectionFactory(
          host,
          port,
          username,
          options,
          _onAuthenticated,
          (type, fingerprint) => _onVerifyHostKey(
            host,
            port,
            type,
            fingerprint,
            acceptNewHostKeys: options.acceptNewHostKeys,
          ),
        );
        _socket = connection.socket;
        _client = connection.client;
      } else {
        // ソケット接続
        _socket = await SSHSocket.connect(
          host,
          port,
          timeout: Duration(seconds: options.timeout),
        );

        // 認証方式に応じたクライアント作成
        if (options.privateKey != null) {
          // 鍵認証
          _client = SSHClient(
            _socket!,
            username: username,
            identities: _parsePrivateKey(
              options.privateKey!,
              options.passphrase,
            ),
            // inventory: SSH-LIFE-018
            onAuthenticated: _onAuthenticated,
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
          _client = SSHClient(
            _socket!,
            username: username,
            onPasswordRequest: () => options.password!,
            onAuthenticated: _onAuthenticated,
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
      }

      // 認証完了を待機
      await _client!.authenticated;

      _state = SshConnectionState.connected;
      _connectionStateController.add(_state);

      // 接続オプションを保存（backend 側は userExecutablePath 経由で取得）
      _connectOptions = options;

      // 一括コマンド実行用の軽量接続では、ポーリング用シェルとkeep-aliveをスキップ。
      // execWithExitCode は専用チャネルを使うため持続的シェルは不要。
      if (!lightweight) {
        // 持続的シェルを開始（ポーリング用）
        // inventory: SSH-LIFE-001
        await _startPersistentShell();
        // Keep-aliveを開始
        // inventory: SSH-LIFE-008
        _startKeepAlive();
      }
    } on SocketException catch (e) {
      _state = SshConnectionState.error;
      _lastError = 'Connection failed: ${e.message}';
      // inventory: SSH-LIFE-020
      await _cleanup();
      throw SshConnectionError(_lastError!, e);
    } on SSHAuthFailError catch (e) {
      _state = SshConnectionState.error;
      _lastError = 'Authentication failed: ${e.message}';
      await _cleanup();
      throw SshAuthenticationError(_lastError!, e);
    } catch (e) {
      _state = SshConnectionState.error;
      _lastError = 'Connection failed: $e';
      await _cleanup();
      throw SshConnectionError(_lastError!, e);
    }
  }

  /// 接続パラメータをバリデート
  void _validateConnectionParams(
    String host,
    int port,
    String username,
    SshConnectOptions options,
  ) {
    if (host.trim().isEmpty) {
      throw SshConnectionError('Host is required');
    }
    if (username.trim().isEmpty) {
      throw SshConnectionError('Username is required');
    }
    if (port < 1 || port > 65535) {
      throw SshConnectionError('Invalid port number: $port');
    }
    if (options.password == null && options.privateKey == null) {
      throw SshAuthenticationError(
        'Either password or privateKey must be provided',
      );
    }
  }

  // inventory: SSH-LIFE-017
  /// ホスト鍵フィンガープリントを検証する。
  ///
  /// 初回接続時は [acceptNewHostKeys] が true なら受け入れて保存し、
  /// false なら拒否する。2回目以降は保存済みフィンガープリントと比較する。
  Future<bool> _onVerifyHostKey(
    String host,
    int port,
    String type,
    Uint8List fingerprint, {
    required bool acceptNewHostKeys,
  }) async {
    final formatted = fingerprint
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');

    final storage = SecureStorageService();
    final known = await storage.getHostKeyFingerprint(host, port, type);

    if (known == null) {
      if (acceptNewHostKeys) {
        await storage.saveHostKeyFingerprint(host, port, type, formatted);
        return true;
      }
      _lastError = 'Unknown host key: $host:$port ($type)';
      return false;
    }

    if (known == formatted) {
      return true;
    }

    _lastError =
        'Host key verification failed: $host:$port ($type) fingerprint changed';
    return false;
  }

  /// 秘密鍵をパース
  List<SSHKeyPair> _parsePrivateKey(String privateKey, String? passphrase) {
    try {
      // SSHKeyPair.fromPem は List<SSHKeyPair> を返す
      final keyPairs = SSHKeyPair.fromPem(privateKey, passphrase);
      if (keyPairs.isEmpty) {
        throw SshAuthenticationError('No valid key found in PEM data');
      }
      return keyPairs;
    } on FormatException catch (e) {
      throw SshAuthenticationError('Invalid private key format: ${e.message}');
    } catch (e) {
      if (e is SshAuthenticationError) rethrow;
      if (passphrase == null && privateKey.contains('ENCRYPTED')) {
        throw SshAuthenticationError(
          'Private key is encrypted, passphrase required',
        );
      }
      throw SshAuthenticationError('Failed to parse private key: $e');
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
    _updateState(SshConnectionState.disconnected);
    _events.onClose?.call();
  }

  /// 状態を更新してストリームに通知
  void _updateState(SshConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _connectionStateController.add(newState);
    }
  }

  /// リソースをクリーンアップ
  Future<void> _cleanup() async {
    // Keep-aliveを停止
    // inventory: SSH-LIFE-010
    _stopKeepAlive();

    // SFTPキャッシュを無効化
    _cachedSftp?.close();
    _cachedSftp = null;

    // 持続的シェルを解放
    await _persistentShell?.dispose();
    _persistentShell = null;
    await _inputShell?.dispose();
    _inputShell = null;

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    _session?.close();
    _session = null;

    // managed PTY（hidden herdr TUI）も確実に終了させる（承認条件 9）。
    final managedPty = _managedPty;
    _managedPty = null;
    if (managedPty != null) {
      await managedPty.close();
    }

    _client?.close();
    _client = null;

    _socket?.close();
    _socket = null;
  }

  /// 持続的シェルを開始
  Future<void> _startPersistentShell() async {
    if (_client == null) return;

    // ポーリング用と入力用の2チャネルを並列で起動（接続時間を増やさない）。
    // どちらの起動失敗も接続自体は継続し、該当機能はexec()にフォールバックする。
    final shells = await Future.wait([_tryStartShell(), _tryStartShell()]);
    _persistentShell = shells[0];
    _inputShell = shells[1];
    // 入力シェルが復活したら Tmux 側に通知（restore trap 再設定等）
    // inventory: SSH-LIFE-004
    onInputShellRebooted?.call();
  }

  // inventory: SSH-LIFE-002
  /// 持続的シェルを1つ起動する。失敗時はnullを返す（例外を投げない）。
  Future<PersistentShell?> _tryStartShell() async {
    final client = _client;
    if (client == null) return null;
    try {
      final factory = _persistentShellFactory;
      if (factory != null) return await factory(client);
      final shell = PersistentShell(client);
      await shell.start();
      return shell;
    } catch (_) {
      return null;
    }
  }

  // inventory: SSH-028
  // inventory: LEGACY-0152
  /// 持続的シェルを再起動
  Future<void> restartPersistentShell() async {
    if (_client == null || !isConnected) return;
    try {
      await _persistentShell?.dispose();
    } catch (_) {
      // dispose失敗は無視して再作成を試みる
    }
    _persistentShell = await _tryStartShell();
  }

  // inventory: SSH-LIFE-003
  // inventory: LEGACY-0153
  /// 入力専用シェルを再起動する（送信失敗時の自己回復用）。
  Future<void> restartInputShell() async {
    if (_client == null || !isConnected) return;
    try {
      await _inputShell?.dispose();
    } catch (_) {
      // dispose失敗は無視して再作成を試みる
    }
    _inputShell = await _tryStartShell();
    // 入力シェルが復活したら Tmux 側に通知
    onInputShellRebooted?.call();
  }

  // tmux 固有のキー送信・restore trap ・復元は Tmux 側の SshTmuxCommandExecutor で担う。

  /// execチャネルを排他的に使用する
  Future<T> _withExecLock<T>(Future<T> Function() fn) async {
    while (_execLock != null) {
      await _execLock!.future;
    }
    final completer = Completer<void>();
    _execLock = completer;
    try {
      return await fn();
    } finally {
      _execLock = null;
      completer.complete();
    }
  }

  /// Keep-aliveを開始
  ///
  /// 定期的に軽量なコマンドを実行して接続が生きているか確認する。
  /// 接続が切れていれば即座にエラー状態に遷移する。
  /// 間隔は動的に調整される（成功時は延長、失敗時は短縮）。
  void _startKeepAlive() {
    _stopKeepAlive();
    _currentKeepAliveIntervalSeconds = 10; // 初期値10秒
    _keepAliveSuccessCount = 0;
    // inventory: SSH-LIFE-009
    _scheduleNextKeepAlive();
  }

  /// 次のKeep-aliveをスケジュール
  void _scheduleNextKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = _timerFactory(
      Duration(seconds: _currentKeepAliveIntervalSeconds),
      () async {
        // inventory: SSH-LIFE-012
        await _sendKeepAlive();
        if (isConnected) {
          _scheduleNextKeepAlive();
        }
      },
    );
  }

  /// Keep-aliveを停止
  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  // inventory: SSH-LIFE-011
  /// Keep-alive間隔を調整
  void _adjustKeepAliveInterval({required bool success}) {
    if (success) {
      _keepAliveSuccessCount++;
      // 3回連続成功で間隔を延長
      if (_keepAliveSuccessCount >= 3) {
        _currentKeepAliveIntervalSeconds =
            (_currentKeepAliveIntervalSeconds + 5).clamp(
              _minKeepAliveIntervalSeconds,
              _maxKeepAliveIntervalSeconds,
            );
        _keepAliveSuccessCount = 0;
      }
    } else {
      // 失敗時は最小間隔に戻す
      _currentKeepAliveIntervalSeconds = _minKeepAliveIntervalSeconds;
      _keepAliveSuccessCount = 0;
    }
  }

  /// Keep-aliveパケットを送信
  Future<void> _sendKeepAlive() async {
    if (!isConnected || _client == null) {
      return;
    }

    try {
      // 持続的シェル経由でkeep-alive（高速）
      // inventory: SSH-033
      // inventory: LEGACY-0159
      await execute(
        CommandRequest(
          command: 'echo ping',
          transport: CommandTransportPreference.persistentPreferred,
          output: CommandOutputRequirement.outputOnly,
          timeout: Duration(seconds: _keepAliveTimeoutSeconds),
        ),
      );
      _adjustKeepAliveInterval(success: true);
    } catch (e) {
      _adjustKeepAliveInterval(success: false);
      // Keep-alive失敗 = 接続切断
      _lastError = 'Connection lost: $e';
      _updateState(SshConnectionState.error);
      _events.onError?.call(SshConnectionError(_lastError!));
      _events.onClose?.call();
    }
  }

  // inventory: SSH-037
  // inventory: LEGACY-0154
  /// インタラクティブシェルを開始する
  ///
  /// [options] シェルオプション
  Future<void> startShell([ShellOptions options = const ShellOptions()]) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }

    try {
      _session = await _client!.shell(
        pty: SSHPtyConfig(
          type: options.term,
          width: options.cols,
          height: options.rows,
        ),
      );

      // stdout/stderrのリスナーを設定
      _stdoutSubscription = _session!.stdout.listen(
        // inventory: SSH-LIFE-013
        _handleData,
        // inventory: SSH-LIFE-014
        onError: _handleError,
        // inventory: SSH-LIFE-015
        onDone: _handleDone,
      );

      _stderrSubscription = _session!.stderr.listen(
        _handleData,
        onError: _handleError,
      );
    } catch (e) {
      throw SshConnectionError('Failed to start shell: $e', e);
    }
  }

  /// データ受信ハンドラ
  void _handleData(Uint8List data) {
    _events.onData?.call(data);
  }

  /// エラーハンドラ
  void _handleError(Object error) {
    _lastError = error.toString();
    _events.onError?.call(error);
  }

  /// 完了ハンドラ
  void _handleDone() {
    _state = SshConnectionState.disconnected;
    _events.onClose?.call();
  }

  // inventory: SSH-042
  /// PTY 付きで [command] を起動し、ライフサイクルを管理する managed process を
  /// 開始する（hidden herdr TUI ホスト用）。
  ///
  /// - 対話シェルを経由せず、dartssh2 の PTY 付き exec（`execute(pty:)`）で
  ///   プロセスを直接所有する（ログインシェルの prompt / rc / job control を回避）。
  /// - stdout は明示的に discard・stderr は末尾 8KB を保持（[ManagedPtyProcess.stderrTail]）。
  /// - 成功 = session 生成 + stdout / stderr 両 stream の監視設置完了
  ///   （プロセス終了は待たない・承認条件 11）。終了検知は
  ///   [ManagedPtyProcess.done]（exit / channel close のいずれか）で行う。
  /// - 二重 start: 既存 managed session を close してから起動（リーク防止）。
  /// - プロセス終了時は [ManagedPtyProcess.done] が発火する。SSH 接続自体は
  ///   維持され、TUI 単体の終了は bridge 側が限定再起動する。
  Future<ManagedPtyProcess> startManagedPty(
    String command, {
    required int cols,
    required int rows,
  }) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }
    // 二重 start: 既存 managed session を close（channel リーク防止）。
    final previous = _managedPty;
    _managedPty = null;
    if (previous != null) {
      await previous.close();
    }
    final session = await _client!.execute(
      command,
      pty: SSHPtyConfig(
        type: 'xterm-256color',
        width: cols,
        height: rows,
      ),
    );
    final process = ManagedPtyProcess._(session);
    _managedPty = process;
    return process;
  }

  /// シェルにデータを書き込む
  ///
  /// [data] 送信データ（文字列）
  // inventory: SSH-038
  @override
  // inventory: LEGACY-0155
  void write(String data) {
    if (!isConnected || _session == null) {
      throw SshConnectionError('Not connected or shell not started');
    }
    _session!.write(utf8.encode(data));
  }

  // inventory: SSH-039
  // inventory: LEGACY-0156
  /// シェルにバイトデータを書き込む
  ///
  /// [data] 送信データ（バイト）
  void writeBytes(Uint8List data) {
    if (!isConnected || _session == null) {
      throw SshConnectionError('Not connected or shell not started');
    }
    _session!.write(data);
  }

  // inventory: SSH-040
  // inventory: LEGACY-0157
  /// ターミナルサイズを変更する
  ///
  /// [cols] カラム数
  /// [rows] 行数
  void resize(int cols, int rows) {
    if (_session == null) {
      return; // シェルが開始されていない場合は何もしない
    }

    try {
      _session!.resizeTerminal(cols, rows);
    } catch (e) {
      // リサイズエラーは警告のみ（致命的ではない）
      _lastError = 'Failed to resize: $e';
    }
  }

  /// 汎用コマンド実行（[CommandExecutor] 実装）。
  ///
  /// [CommandRequest.transport] / [CommandRequest.output] に基づいて
  /// ephemeral（毎回チャネル開閉）または persistent（持続的シェル）を
  /// ルーティングする（Codex 根本設計レビュー・バグ2 根本対応）。
  ///
  /// - `persistentPreferred + separatedOutput` は最初から ephemeral に
  ///   ルーティングする（PTY では分離できないため）。
  /// - `persistentOnly` は shell が利用不能なら例外を投げる。
  /// - timeout は `execute()` 全体の deadline。timeout 後の自動再実行はしない。
  @override
  Future<CommandResult> execute(CommandRequest request) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }
    if (!request.isValid) {
      throw ArgumentError(
        'Invalid CommandRequest: persistentOnly + separatedOutput is impossible '
        '(PTY cannot separate stdout/stderr): $request',
      );
    }

    final useEphemeral =
        request.output == CommandOutputRequirement.separatedOutput ||
            request.transport == CommandTransportPreference.ephemeralOnly;

    if (useEphemeral) {
      final result = await _executeEphemeral(request);
      return CommandResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.separated,
        actualTransport: CommandTransport.ephemeral,
      );
    }

    // persistent 経路（outputOnly / exitCode・PTY では merged になる）。
    if (_persistentShell == null || !_persistentShell!.isStarted) {
      if (request.transport == CommandTransportPreference.persistentOnly) {
        throw SshConnectionError('Persistent shell is not available');
      }
      final result = await _executeEphemeral(request);
      return CommandResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.separated,
        actualTransport: CommandTransport.ephemeral,
      );
    }

    final captureExitCode =
        request.output == CommandOutputRequirement.exitCode;
    try {
      final result = captureExitCode
          ? await _persistentShell!.execWithExitCode(
              request.command,
              timeout: request.timeout,
            )
          : (
              output: await _persistentShell!.exec(
                request.command,
                timeout: request.timeout,
              ),
              exitCode: null,
            );
      return CommandResult(
        mergedOutput: result.output,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.merged,
        actualTransport: CommandTransport.persistent,
      );
    } on PersistentShellError catch (e) {
      // シェルセッションが切断された場合のみ再起動して再試行する。
      // timeout（stale frame 混入防止で shell が破棄された）は自動再実行
      // しない（実行結果が不明のため・mutation の二重適用防止）。
      if (e.message.contains('closed') || e.message.contains('disposed')) {
        await restartPersistentShell();
        final result = captureExitCode
            ? await _persistentShell!.execWithExitCode(
                request.command,
                timeout: request.timeout,
              )
            : (
                output: await _persistentShell!.exec(
                  request.command,
                  timeout: request.timeout,
                ),
                exitCode: null,
              );
        return CommandResult(
          mergedOutput: result.output,
          exitCode: result.exitCode,
          outputSeparation: CommandOutputSeparation.merged,
          actualTransport: CommandTransport.persistent,
        );
      }
      // その他の persistent エラー（persistentOnly はフォールバック不可）。
      if (request.transport == CommandTransportPreference.persistentOnly) {
        rethrow;
      }
      final result = await _executeEphemeral(request);
      return CommandResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        outputSeparation: CommandOutputSeparation.separated,
        actualTransport: CommandTransport.ephemeral,
      );
    }
  }

  /// ephemeral（毎回チャネル開閉 + exec ロック直列化）でコマンドを実行する。
  Future<({String stdout, String stderr, int? exitCode})> _executeEphemeral(
    CommandRequest request,
  ) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }

    try {
      final resolvedCommand = request.command;
      return await _withExecLock(() async {
        // ignore: avoid_init_to_null
        SSHSession? session = null;
        // ignore: avoid_init_to_null
        int? exitCode = null;
        final stdoutBytes = <int>[];
        final stderrBytes = <int>[];
        try {
          session = await _client!.execute(resolvedCommand);

          final stdoutCompleter = Completer<void>();
          final stderrCompleter = Completer<void>();

          session.stdout.listen(
            (data) => stdoutBytes.addAll(data),
            onDone: () => stdoutCompleter.complete(),
            onError: (e) => stdoutCompleter.completeError(e),
          );

          session.stderr.listen(
            (data) => stderrBytes.addAll(data),
            onDone: () => stderrCompleter.complete(),
            onError: (e) => stderrCompleter.completeError(e),
          );

          if (request.timeout != null) {
            await Future.wait([
              stdoutCompleter.future,
              stderrCompleter.future,
            ]).timeout(request.timeout!);
          } else {
            await Future.wait([stdoutCompleter.future, stderrCompleter.future]);
          }

          exitCode = session.exitCode;
        } finally {
          session?.close();
        }

        return (
          stdout: utf8.decode(stdoutBytes, allowMalformed: true),
          stderr: utf8.decode(stderrBytes, allowMalformed: true),
          exitCode: exitCode,
        );
      });
    } on TimeoutException {
      throw SshConnectionError('Command execution timed out');
    } catch (e) {
      throw SshConnectionError('Failed to execute command: $e', e);
    }
  }

  // inventory: SSH-035
  // inventory: LEGACY-0160
  /// イベントハンドラを設定する
  void setEventHandlers(SshEvents events) {
    _events = events;
  }

  // inventory: SSH-036
  // inventory: LEGACY-0161
  /// イベントハンドラを更新する
  void updateEventHandlers({
    void Function(Uint8List data)? onData,
    void Function()? onClose,
    void Function(Object error)? onError,
  }) {
    _events = _events.copyWith(
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
    await _connectionStateController.close();
  }
}

// inventory: SSH-043
/// managed PTY process（hidden herdr TUI ホスト用・[ SshClient.startManagedPty] の成果物）。
///
/// - stdout: 明示的に discard（購読して破棄。SSH channel window の詰まり防止）
/// - stderr: 末尾 [maxStderrTail] バイトをリングバッファで保持（診断用）
/// - 終了検知: [done] が「exit / channel close のいずれか」で発火する
///   （`session.done` + `stdout.done` + `stderr.done` のすべてを監視・承認条件 10）
/// - exitCode: [SSHSession.exitCode] getter から取得（stream でなく）
/// - [resize]: 失敗時は throw（収束判定のため握り潰さない）
/// - [close]: SIGTERM 送信 → done 待ち → channel close（冪等）
class ManagedPtyProcess {
  ManagedPtyProcess._(this._session, {int maxStderrTail = 8192}) {
    // stdout/stderr の監視と完了検知を開始（完了は [done] が通知する）。
    unawaited(_trackCompletion(maxStderrTail));
  }

  static const int _closeTimeoutMs = 500;

  final SSHSession _session;
  final List<int> _stderrTail = <int>[];
  final StreamController<void> _doneController =
      StreamController<void>.broadcast();
  bool _closed = false;

  /// プロセス終了（exit / channel close / [close] のいずれか）を通知する。
  Stream<void> get done => _doneController.stream;

  /// プロセス終了後の exit code（未終了または exit 非報告なら null）。
  int? get exitCode => _session.exitCode;

  /// 終了コードの代わりにシグナルで終了した場合のシグナル名（無ければ null）。
  String? get exitSignalName => _session.exitSignal?.signalName;

  /// stderr の末尾（最大 8KB・診断用）。
  String get stderrTail => utf8.decode(_stderrTail, allowMalformed: true);

  /// PTY のウィンドウサイズを変更する（SSH window-change → SIGWINCH）。
  ///
  /// 失敗は throw（成功判定のため握り潰さない）。終了後の呼び出しも拒否する。
  void resize(int cols, int rows) {
    if (_closed) {
      throw StateError('Managed PTY is already closed');
    }
    _session.resizeTerminal(cols, rows);
  }

  /// プロセスを終了する（SIGTERM → done 待ち → channel close・冪等）。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _session.kill(SSHSignal.TERM);
    } catch (_) {
      // シグナル非対応のサーバでは channel close で代替する。
    }
    try {
      await _session.done.timeout(const Duration(milliseconds: _closeTimeoutMs));
    } catch (_) {
      // タイムアウトしても channel close で強制終了する。
    }
    try {
      _session.close();
    } catch (_) {}
  }

  /// stdout / stderr の監視設置と完了検知（承認条件 10・11）。
  ///
  /// - stdout: データを破棄（discard）しながら done を監視
  /// - stderr: 末尾 [maxStderrTail] バイトを保持しながら done を監視
  /// - 3 つの完了（session.done / stdout.done / stderr.done）を待って [done] を発火
  Future<void> _trackCompletion(int maxStderrTail) async {
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    // stdout: 明示 discard（channel window 詰まり防止）。
    _session.stdout.listen(
      (_) {},
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      onError: (Object _) {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );
    // stderr: 末尾保持 + done 監視。
    _session.stderr.listen(
      (data) {
        _stderrTail.addAll(data);
        if (_stderrTail.length > maxStderrTail) {
          _stderrTail.removeRange(0, _stderrTail.length - maxStderrTail);
        }
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      onError: (Object _) {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );
    await Future.wait([
      _session.done.catchError((Object _) {}),
      stdoutDone.future,
      stderrDone.future,
    ]);
    if (!_doneController.isClosed) {
      _doneController.add(null);
    }
  }
}

// inventory: SSH-044
/// SSHクライアントを作成する
SshClient createSshClient() {
  return SshClient();
}
