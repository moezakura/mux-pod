import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// SshProxyTunneler テスト用の fake 群（ssh_client_fakes.dart の
/// FakeSocket / FakeRawSshClient の noSuchMethod パターンに準拠）。

/// `forwardLocal` の戻り値となる偽の転送チャネル（SSHForwardChannel は
/// dartssh2 側で SSHSocket を implements 済み・アダプタ不要）。
class FakeForwardChannel implements SSHForwardChannel {
  FakeForwardChannel({required this.remoteHost, required this.remotePort});

  final String remoteHost;
  final int remotePort;

  final _stream = StreamController<Uint8List>();
  final _sink = StreamController<List<int>>();
  bool closed = false;

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  StreamSink<List<int>> get sink => _sink.sink;

  @override
  Future<void> get done => _stream.done;

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _stream.close();
    await _sink.close();
  }

  @override
  void destroy() => unawaited(close());

  @override
  Future<void> flush() async {}
}

/// hop 用の偽 SSHClient。
///
/// `authenticated` の完了制御（[completeAuthentication] /
/// [failAuthentication] / 未完了）と `forwardLocal` の振る舞い
/// （FakeForwardChannel 返却 / [forwardError] throw /
/// [forwardNeverCompletes] で完了しない）をテストから制御できる。
class FakeProxyHopClient implements SSHClient {
  FakeProxyHopClient();

  bool _authCompleted = false;
  Object? _authError;

  /// forwardLocal に渡された転送先の記録。
  final forwarded = <({String host, int port})>[];

  /// forwardLocal 呼び出し時に throw するエラー（null なら正常系）。
  Object? forwardError;

  /// forwardLocal を完了させない（MR-1 タイムアウト検証用）。
  bool forwardNeverCompletes = false;

  bool closed = false;

  /// forwardLocal が完了したチャネル（最後に返したもの）。
  FakeForwardChannel? lastChannel;

  void completeAuthentication() => _authCompleted = true;

  void failAuthentication(Object error) => _authError = error;

  /// dartssh2 同様、listener が同期的に付く形で結果を返す
  /// （completeError を直接使うと listener 付与前の未ハンドルエラーが
  /// テストゾーンへ逃げるため）。
  @override
  Future<void> get authenticated {
    final error = _authError;
    if (error != null) {
      return Future<void>.error(error);
    }
    if (_authCompleted) {
      return Future<void>.value();
    }
    // 完了しない（MR-1 タイムアウト検証用）
    return Completer<void>().future;
  }

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    forwarded.add((host: remoteHost, port: remotePort));
    final error = forwardError;
    if (error != null) throw error;
    if (forwardNeverCompletes) {
      return Completer<SSHForwardChannel>().future;
    }
    final channel = FakeForwardChannel(
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
    lastChannel = channel;
    return channel;
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
