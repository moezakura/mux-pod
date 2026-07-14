import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'persistent_shell.dart';

/// SSH接続エラー
class SshConnectionError implements Exception {
  final String message;
  final Object? cause;

  SshConnectionError(this.message, [this.cause]);

  @override
  String toString() => 'SshConnectionError: $message${cause != null ? ' ($cause)' : ''}';
}

/// SSH認証エラー
class SshAuthenticationError implements Exception {
  final String message;
  final Object? cause;

  SshAuthenticationError(this.message, [this.cause]);

  @override
  String toString() => 'SshAuthenticationError: $message${cause != null ? ' ($cause)' : ''}';
}

/// SSH接続オプション
class SshConnectOptions {
  /// パスワード認証時のパスワード
  final String? password;

  /// 鍵認証時の秘密鍵（PEM形式）
  final String? privateKey;

  /// 秘密鍵のパスフレーズ
  final String? passphrase;

  /// ユーザー指定のtmuxパス（nullなら自動検出）
  final String? tmuxPath;

  /// 接続タイムアウト（秒）
  final int timeout;

  const SshConnectOptions({
    this.password,
    this.privateKey,
    this.passphrase,
    this.tmuxPath,
    this.timeout = 30,
  });
}

/// シェルオプション
class ShellOptions {
  /// ターミナルタイプ
  final String term;

  /// カラム数
  final int cols;

  /// 行数
  final int rows;

  const ShellOptions({
    this.term = 'xterm-256color',
    this.cols = 80,
    this.rows = 24,
  });
}

/// SSH接続イベント
class SshEvents {
  /// データ受信時
  final void Function(Uint8List data)? onData;

  /// 接続クローズ時
  final void Function()? onClose;

  /// エラー発生時
  final void Function(Object error)? onError;

  const SshEvents({
    this.onData,
    this.onClose,
    this.onError,
  });

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

/// SSH接続状態
enum SshConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// SSHクライアント
///
/// dartssh2をラップし、SSH接続を管理する。
class SshClient {
  SSHClient? _client;
  SSHSession? _session;
  SSHSocket? _socket;
  SftpClient? _cachedSftp;

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

  /// 検出されたtmuxバイナリの絶対パス
  String? _tmuxPath;

  /// execチャネル排他制御用ロック
  Completer<void>? _execLock;

  /// tmuxの絶対パス（未検出なら null）
  String? get tmuxPath => _tmuxPath;

  /// Keep-aliveタイマー
  Timer? _keepAliveTimer;

  /// 接続監視用のStreamController
  final _connectionStateController = StreamController<SshConnectionState>.broadcast();

  /// 接続状態のストリーム（外部から監視用）
  Stream<SshConnectionState> get connectionStateStream => _connectionStateController.stream;

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

  /// 現在の接続状態
  SshConnectionState get state => _state;

  /// 接続中かどうか
  bool get isConnected => _state == SshConnectionState.connected;

  /// 最後のエラーメッセージ
  String? get lastError => _lastError;

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
    _validateConnectionParams(host, port, username, options);

    _state = SshConnectionState.connecting;
    _lastError = null;

    try {
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
          identities: _parsePrivateKey(options.privateKey!, options.passphrase),
          onAuthenticated: _onAuthenticated,
        );
      } else if (options.password != null) {
        // パスワード認証
        _client = SSHClient(
          _socket!,
          username: username,
          onPasswordRequest: () => options.password!,
          onAuthenticated: _onAuthenticated,
        );
      } else {
        throw SshAuthenticationError('No authentication method provided');
      }

      // 認証完了を待機
      await _client!.authenticated;

      _state = SshConnectionState.connected;
      _connectionStateController.add(_state);

      // tmuxパス検出（ユーザー指定があればそれを使用、なければ自動検出）
      if (options.tmuxPath != null && options.tmuxPath!.isNotEmpty) {
        // ユーザー指定パスの存在確認
        final verifyExitCode = await _withExecLock(() async {
          final session = await _client!.execute('test -x ${_shSingleQuote(options.tmuxPath!)}');
          await session.stdout.drain();
          await session.stderr.drain();
          final code = session.exitCode;
          session.close();
          return code;
        });
        if (verifyExitCode == 0) {
          _tmuxPath = options.tmuxPath;
          debugPrint('connect: user-specified tmux path verified: $_tmuxPath');
        } else {
          debugPrint('connect: user-specified tmux path not found: ${options.tmuxPath}');
        }
      } else {
        await _detectTmuxPath();
      }

      // 一括コマンド実行用の軽量接続では、ポーリング用シェルとkeep-aliveをスキップ。
      // execWithExitCode は専用チャネルを使うため持続的シェルは不要。
      if (!lightweight) {
        // 持続的シェルを開始（ポーリング用）
        await _startPersistentShell();
        // Keep-aliveを開始
        _startKeepAlive();
      }
    } on SocketException catch (e) {
      _state = SshConnectionState.error;
      _lastError = 'Connection failed: ${e.message}';
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
        throw SshAuthenticationError('Private key is encrypted, passphrase required');
      }
      throw SshAuthenticationError('Failed to parse private key: $e');
    }
  }

  /// 認証完了コールバック
  void _onAuthenticated() {
    // 認証成功
  }

  /// 接続を切断する
  Future<void> disconnect() async {
    await _cleanup();
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
  }

  /// 持続的シェルを1つ起動する。失敗時はnullを返す（例外を投げない）。
  Future<PersistentShell?> _tryStartShell() async {
    final client = _client;
    if (client == null) return null;
    try {
      final shell = PersistentShell(client);
      await shell.start();
      return shell;
    } catch (_) {
      return null;
    }
  }

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

  /// 入力専用シェルを再起動する（送信失敗時の自己回復用）。
  Future<void> _restartInputShell() async {
    if (_client == null || !isConnected) return;
    try {
      await _inputShell?.dispose();
    } catch (_) {
      // dispose失敗は無視して再作成を試みる
    }
    _inputShell = await _tryStartShell();
  }

  /// キー送信などの出力不要コマンドを低遅延で送信する。
  ///
  /// 専用のfire-and-forgetチャネルに書き込むだけで完了する。[exec]と違い
  /// チャネル開閉・execロック・往復待ちがないため、高pingの回線でも入力が
  /// 詰まらない（結果はポーリングで反映される）。
  /// 高速チャネルが使えない場合は信頼性優先で[exec]にフォールバックする。
  Future<void> sendKeysCommand(String command) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }

    final input = _inputShell;
    if (input != null && input.isStarted) {
      try {
        input.sendNoWait(_resolveTmuxCommand(command));
        return;
      } on PersistentShellError {
        // 高速チャネルが切れた: 次回のために再起動し、今回はexecへフォールバック
        unawaited(_restartInputShell());
      }
    }

    // フォールバック: 従来のexec（内部で_resolveTmuxCommandを実行）
    await exec(command);
  }

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

  /// execチャネル経由でtmuxの絶対パスを検出
  ///
  /// Step 1: ログインシェル経由で `command -v tmux` を実行
  /// Step 2: 失敗時、既知の候補パスで `test -x` フォールバック
  Future<void> _detectTmuxPath() async {
    if (_client == null || !isConnected) return;

    // Step 1: ログインシェル経由で検出
    try {
      final path = await _withExecLock(() async {
        final session = await _client!.execute(
          r"$SHELL -lc 'command -v tmux'",
        );
        final stdoutBytes = <int>[];
        await session.stdout.forEach((data) => stdoutBytes.addAll(data));
        await session.stderr.drain();
        session.close();
        return utf8.decode(stdoutBytes, allowMalformed: true).trim();
      });
      if (path.isNotEmpty && path.startsWith('/')) {
        _tmuxPath = path;
        debugPrint('_detectTmuxPath: found via login shell: $path');
        return;
      }
    } catch (e) {
      debugPrint('_detectTmuxPath: login shell detection failed: $e');
    }

    // Step 2: 既知パスのフォールバック
    const candidates = [
      '/opt/homebrew/bin/tmux',
      '/usr/local/bin/tmux',
      '/usr/bin/tmux',
    ];

    for (final candidate in candidates) {
      try {
        final exitCode = await _withExecLock(() async {
          final session = await _client!.execute('test -x $candidate');
          await session.stdout.drain();
          await session.stderr.drain();
          final code = session.exitCode;
          session.close();
          return code;
        });
        if (exitCode == 0) {
          _tmuxPath = candidate;
          debugPrint('_detectTmuxPath: found via fallback: $candidate');
          return;
        }
      } catch (e) {
        debugPrint('_detectTmuxPath: error checking $candidate: $e');
      }
    }
    debugPrint('_detectTmuxPath: tmux not found');
  }

  /// コマンド内の `tmux` を検出済み絶対パスに置換
  String _resolveTmuxCommand(String command) {
    if (_tmuxPath == null) return command;
    final resolved = command.replaceAllMapped(
      RegExp(r'(^|;\s*)tmux\b'),
      (m) => '${m[1]}$_tmuxPath',
    );
    return resolved;
  }

  /// シェル引数を単一引用符で安全に囲む（ユーザー入力のtmuxパス等に使用）。
  String _shSingleQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

  /// Keep-aliveを開始
  ///
  /// 定期的に軽量なコマンドを実行して接続が生きているか確認する。
  /// 接続が切れていれば即座にエラー状態に遷移する。
  /// 間隔は動的に調整される（成功時は延長、失敗時は短縮）。
  void _startKeepAlive() {
    _stopKeepAlive();
    _currentKeepAliveIntervalSeconds = 10; // 初期値10秒
    _keepAliveSuccessCount = 0;
    _scheduleNextKeepAlive();
  }

  /// 次のKeep-aliveをスケジュール
  void _scheduleNextKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer(
      Duration(seconds: _currentKeepAliveIntervalSeconds),
      () async {
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

  /// Keep-alive間隔を調整
  void _adjustKeepAliveInterval({required bool success}) {
    if (success) {
      _keepAliveSuccessCount++;
      // 3回連続成功で間隔を延長
      if (_keepAliveSuccessCount >= 3) {
        _currentKeepAliveIntervalSeconds = (_currentKeepAliveIntervalSeconds + 5)
            .clamp(_minKeepAliveIntervalSeconds, _maxKeepAliveIntervalSeconds);
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
      await execPersistent(
        'echo ping',
        timeout: Duration(seconds: _keepAliveTimeoutSeconds),
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
        _handleData,
        onError: _handleError,
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

  /// シェルにデータを書き込む
  ///
  /// [data] 送信データ（文字列）
  void write(String data) {
    if (!isConnected || _session == null) {
      throw SshConnectionError('Not connected or shell not started');
    }
    _session!.write(utf8.encode(data));
  }

  /// シェルにバイトデータを書き込む
  ///
  /// [data] 送信データ（バイト）
  void writeBytes(Uint8List data) {
    if (!isConnected || _session == null) {
      throw SshConnectionError('Not connected or shell not started');
    }
    _session!.write(data);
  }

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

  /// コマンドを実行して結果を取得する
  ///
  /// [command] 実行コマンド
  /// [timeout] タイムアウト時間
  /// 戻り値: コマンド出力
  Future<String> exec(String command, {Duration? timeout}) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }

    try {
      final resolvedCommand = _resolveTmuxCommand(command);
      return await _withExecLock(() async {
        final session = await _client!.execute(resolvedCommand);

        // 出力を収集（バイト列として収集し、最後にデコード）
        final stdoutBytes = <int>[];
        final stderrBytes = <int>[];

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

        // タイムアウト付きで完了を待機
        if (timeout != null) {
          await Future.wait([
            stdoutCompleter.future,
            stderrCompleter.future,
          ]).timeout(timeout);
        } else {
          await Future.wait([
            stdoutCompleter.future,
            stderrCompleter.future,
          ]);
        }

        session.close();

        // バイト列をUTF-8デコード（不正なバイトは置換文字に）
        final stdout = utf8.decode(stdoutBytes, allowMalformed: true);
        final stderr = utf8.decode(stderrBytes, allowMalformed: true);

        // stderrがあればエラーとして扱う（オプション）
        if (stderr.isNotEmpty) {
          return stdout + stderr;
        }

        return stdout;
      });
    } on TimeoutException {
      debugPrint('exec: timed out');
      throw SshConnectionError('Command execution timed out');
    } catch (e) {
      debugPrint('exec: error=$e');
      throw SshConnectionError('Failed to execute command: $e', e);
    }
  }

  /// 持続的シェル経由でコマンドを実行（高速）
  ///
  /// チャネル開閉のオーバーヘッドを排除し、1 RTT程度で実行可能。
  /// ポーリングなど高頻度のコマンド実行に適している。
  ///
  /// [command] 実行コマンド
  /// [timeout] タイムアウト時間
  /// 戻り値: コマンド出力
  Future<String> execPersistent(String command, {Duration? timeout}) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }

    final resolvedCommand = _resolveTmuxCommand(command);

    // 持続的シェルが利用できない場合は従来のexec()にフォールバック
    if (_persistentShell == null || !_persistentShell!.isStarted) {
      return exec(resolvedCommand, timeout: timeout);
    }

    try {
      return await _persistentShell!.exec(resolvedCommand, timeout: timeout);
    } on PersistentShellError catch (e) {
      // シェルセッションが切断された場合は再起動を試みる
      if (e.message.contains('closed') || e.message.contains('disposed')) {
        try {
          await restartPersistentShell();
          return await _persistentShell!.exec(resolvedCommand, timeout: timeout);
        } catch (_) {
          // 再起動も失敗した場合は従来のexec()にフォールバック
          return exec(resolvedCommand, timeout: timeout);
        }
      }
      // その他のエラーは従来のexec()にフォールバック
      return exec(resolvedCommand, timeout: timeout);
    }
  }

  /// コマンドを実行して終了コードを取得する
  ///
  /// [command] 実行コマンド
  /// 戻り値: (stdout, stderr, exitCode)
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    if (!isConnected || _client == null) {
      throw SshConnectionError('Not connected');
    }

    try {
      final resolvedCommand = _resolveTmuxCommand(command);
      return await _withExecLock(() async {
        final session = await _client!.execute(resolvedCommand);

        // バイト列として蓄積（チャンク単位デコードによるUTF-8境界分割を防止）
        final stdoutBytes = <int>[];
        final stderrBytes = <int>[];

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

        if (timeout != null) {
          await Future.wait([
            stdoutCompleter.future,
            stderrCompleter.future,
          ]).timeout(timeout);
        } else {
          await Future.wait([
            stdoutCompleter.future,
            stderrCompleter.future,
          ]);
        }

        final exitCode = session.exitCode;
        session.close();

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

  /// イベントハンドラを設定する
  void setEventHandlers(SshEvents events) {
    _events = events;
  }

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

  /// リソースを解放する
  Future<void> dispose() async {
    await disconnect();
    await _connectionStateController.close();
  }
}

/// SSHクライアントを作成する
SshClient createSshClient() {
  return SshClient();
}
