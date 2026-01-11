import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

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

  /// 接続タイムアウト（秒）
  final int timeout;

  const SshConnectOptions({
    this.password,
    this.privateKey,
    this.passphrase,
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

  SshConnectionState _state = SshConnectionState.disconnected;
  SshEvents _events = const SshEvents();
  String? _lastError;

  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;

  /// 現在の接続状態
  SshConnectionState get state => _state;

  /// 接続中かどうか
  bool get isConnected => _state == SshConnectionState.connected;

  /// 最後のエラーメッセージ
  String? get lastError => _lastError;

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
    _state = SshConnectionState.disconnected;
    _events.onClose?.call();
  }

  /// リソースをクリーンアップ
  Future<void> _cleanup() async {
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
      final session = await _client!.execute(command);

      // 出力を収集
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final stdoutCompleter = Completer<void>();
      final stderrCompleter = Completer<void>();

      session.stdout.listen(
        (data) => stdout.write(utf8.decode(data)),
        onDone: () => stdoutCompleter.complete(),
        onError: (e) => stdoutCompleter.completeError(e),
      );

      session.stderr.listen(
        (data) => stderr.write(utf8.decode(data)),
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

      // stderrがあればエラーとして扱う（オプション）
      final result = stdout.toString();
      if (stderr.isNotEmpty) {
        // stderrも結果に含める（tmuxコマンドなどはstderrに出力することがある）
        return result + stderr.toString();
      }

      return result;
    } on TimeoutException {
      throw SshConnectionError('Command execution timed out');
    } catch (e) {
      throw SshConnectionError('Failed to execute command: $e', e);
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
      final session = await _client!.execute(command);

      final stdout = StringBuffer();
      final stderr = StringBuffer();

      final stdoutCompleter = Completer<void>();
      final stderrCompleter = Completer<void>();

      session.stdout.listen(
        (data) => stdout.write(utf8.decode(data)),
        onDone: () => stdoutCompleter.complete(),
        onError: (e) => stdoutCompleter.completeError(e),
      );

      session.stderr.listen(
        (data) => stderr.write(utf8.decode(data)),
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
        stdout: stdout.toString(),
        stderr: stderr.toString(),
        exitCode: exitCode,
      );
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
  }
}

/// SSHクライアントを作成する
SshClient createSshClient() {
  return SshClient();
}
