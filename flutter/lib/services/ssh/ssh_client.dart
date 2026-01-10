import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/connection.dart';

/// SSH接続状態
enum ConnectionStatus {
  disconnected,
  connecting,
  authenticating,
  connected,
  error,
}

/// SSH接続状態変更イベント
class ConnectionStateEvent {
  final String connectionId;
  final ConnectionStatus status;
  final String? error;
  final int? latencyMs;

  const ConnectionStateEvent({
    required this.connectionId,
    required this.status,
    this.error,
    this.latencyMs,
  });
}

/// コマンド実行結果
class SshExecResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  const SshExecResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  bool get success => exitCode == 0;
}

/// SSHシェルセッション
class SshShellSession {
  SshShellSession({
    required this.shell,
    required this.connectionId,
  });

  final SSHSession shell;
  final String connectionId;

  /// シェル出力ストリーム
  Stream<Uint8List> get stdout => shell.stdout;

  /// シェルエラー出力ストリーム
  Stream<Uint8List> get stderr => shell.stderr;

  /// シェル終了Future
  Future<void> get done => shell.done;

  /// データ送信
  void write(Uint8List data) {
    shell.write(data);
  }

  /// 文字列送信（UTF-8エンコード）
  void writeString(String data) {
    shell.write(utf8.encode(data));
  }

  /// PTYサイズ変更
  Future<void> resize(int width, int height) async {
    shell.resizeTerminal(width, height);
  }

  /// シェルクローズ
  Future<void> close() async {
    shell.close();
  }
}

/// SSHクライアント
///
/// dartssh2をラップしてSSH接続を管理する。
class SshClient {
  SshClient();

  final Map<String, SSHClient> _clients = {};
  final Map<String, ConnectionStatus> _statuses = {};
  final _stateController = StreamController<ConnectionStateEvent>.broadcast();

  /// 接続状態ストリーム
  Stream<ConnectionStateEvent> get connectionState => _stateController.stream;

  /// パスワード認証で接続
  Future<void> connectWithPassword({
    required Connection connection,
    required String password,
  }) async {
    final id = connection.id;

    try {
      _updateStatus(id, ConnectionStatus.connecting);

      final stopwatch = Stopwatch()..start();

      final socket = await SSHSocket.connect(
        connection.host,
        connection.port,
        timeout: Duration(seconds: connection.timeout),
      );

      _updateStatus(id, ConnectionStatus.authenticating);

      final client = SSHClient(
        socket,
        username: connection.username,
        onPasswordRequest: () => password,
        keepAliveInterval: connection.keepAliveInterval > 0
            ? Duration(seconds: connection.keepAliveInterval)
            : null,
      );

      stopwatch.stop();

      _clients[id] = client;
      _updateStatus(id, ConnectionStatus.connected,
          latencyMs: stopwatch.elapsedMilliseconds);

      // 接続クローズ時の処理
      client.done.then((_) {
        _clients.remove(id);
        _updateStatus(id, ConnectionStatus.disconnected);
      });
    } catch (e) {
      _updateStatus(id, ConnectionStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// 鍵認証で接続
  Future<void> connectWithKey({
    required Connection connection,
    required String privateKeyPem,
    String? passphrase,
  }) async {
    final id = connection.id;

    try {
      _updateStatus(id, ConnectionStatus.connecting);

      final stopwatch = Stopwatch()..start();

      final socket = await SSHSocket.connect(
        connection.host,
        connection.port,
        timeout: Duration(seconds: connection.timeout),
      );

      _updateStatus(id, ConnectionStatus.authenticating);

      final identities = SSHKeyPair.fromPem(privateKeyPem, passphrase);

      final client = SSHClient(
        socket,
        username: connection.username,
        identities: identities,
        keepAliveInterval: connection.keepAliveInterval > 0
            ? Duration(seconds: connection.keepAliveInterval)
            : null,
      );

      stopwatch.stop();

      _clients[id] = client;
      _updateStatus(id, ConnectionStatus.connected,
          latencyMs: stopwatch.elapsedMilliseconds);

      // 接続クローズ時の処理
      client.done.then((_) {
        _clients.remove(id);
        _updateStatus(id, ConnectionStatus.disconnected);
      });
    } catch (e) {
      _updateStatus(id, ConnectionStatus.error, error: e.toString());
      rethrow;
    }
  }

  /// 接続状態取得
  ConnectionStatus getStatus(String connectionId) {
    return _statuses[connectionId] ?? ConnectionStatus.disconnected;
  }

  /// シェルセッション開始
  Future<SshShellSession> startShell({
    required String connectionId,
    int width = 80,
    int height = 24,
    String term = 'xterm-256color',
  }) async {
    final client = _clients[connectionId];
    if (client == null) {
      throw StateError('Not connected: $connectionId');
    }

    final shell = await client.shell(
      pty: SSHPtyConfig(
        type: term,
        width: width,
        height: height,
      ),
    );

    return SshShellSession(
      shell: shell,
      connectionId: connectionId,
    );
  }

  /// コマンド実行
  Future<SshExecResult> exec({
    required String connectionId,
    required String command,
  }) async {
    final client = _clients[connectionId];
    if (client == null) {
      throw StateError('Not connected: $connectionId');
    }

    final session = await client.execute(command);

    final stdout = StringBuffer();
    final stderr = StringBuffer();

    await for (final data in session.stdout) {
      stdout.write(utf8.decode(data, allowMalformed: true));
    }

    await for (final data in session.stderr) {
      stderr.write(utf8.decode(data, allowMalformed: true));
    }

    await session.done;

    return SshExecResult(
      stdout: stdout.toString(),
      stderr: stderr.toString(),
      exitCode: session.exitCode ?? -1,
    );
  }

  /// 切断
  Future<void> disconnect(String connectionId) async {
    final client = _clients.remove(connectionId);
    if (client != null) {
      client.close();
      _updateStatus(connectionId, ConnectionStatus.disconnected);
    }
  }

  /// 全接続切断
  Future<void> disconnectAll() async {
    for (final id in _clients.keys.toList()) {
      await disconnect(id);
    }
  }

  /// 接続済みか確認
  bool isConnected(String connectionId) {
    return _statuses[connectionId] == ConnectionStatus.connected;
  }

  /// クライアント取得（内部用）
  SSHClient? getClient(String connectionId) {
    return _clients[connectionId];
  }

  /// 状態更新
  void _updateStatus(
    String connectionId,
    ConnectionStatus status, {
    String? error,
    int? latencyMs,
  }) {
    _statuses[connectionId] = status;
    _stateController.add(ConnectionStateEvent(
      connectionId: connectionId,
      status: status,
      error: error,
      latencyMs: latencyMs,
    ));
  }

  /// リソース解放
  void dispose() {
    disconnectAll();
    _stateController.close();
  }
}
