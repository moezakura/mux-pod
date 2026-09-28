// P5: SshResourceManager テスト（計画 §L4 テスト6）。
// attachJumpClients → disposeAll の close 順序・attach は認証待ち前に行われ
// target 認証失敗でも jump が閉じる（M5）・facade の SshProxyConnectionError
// pass-through（テスト3(d) の facade 側アサート）。
import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_connection_error.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_tunneler.dart';
import 'package:flutter_muxpod/services/ssh/ssh_resource_manager.dart';

import 'helpers/ssh_client_fakes.dart' show FakeRawSshClient, FakeSocket;
import 'helpers/ssh_proxy_fakes.dart';

/// close 順序を記録する target client。
class LoggedRawClient extends FakeRawSshClient {
  LoggedRawClient(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  void close() {
    log.add(name);
    super.close();
  }
}

/// close 順序を記録する hop client。
class LoggedHopClient extends FakeProxyHopClient {
  LoggedHopClient(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  void close() {
    log.add(name);
    super.close();
  }
}

/// トランスポートが即座に死ぬ転送チャネル（target 認証失敗の再現用）。
class BrokenForwardChannel implements SSHForwardChannel {
  final _sink = StreamController<List<int>>();
  bool closed = false;

  @override
  Stream<Uint8List> get stream => Stream<Uint8List>.error(StateError('broken'));

  @override
  StreamSink<List<int>> get sink => _sink.sink;

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  void destroy() {
    closed = true;
  }

  @override
  Future<void> flush() async {}
}

/// forwardLocal が壊れたチャネルを返す hop client（target 認証失敗の再現用）。
class BrokenForwardHopClient extends FakeProxyHopClient {
  final brokenChannel = BrokenForwardChannel();

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    forwarded.add((host: remoteHost, port: remotePort));
    return brokenChannel;
  }
}

/// 常に hop 座標付きエラーを投げる fake tunneler。
class ThrowingTunneler extends SshProxyTunneler {
  ThrowingTunneler() : super(l10n: () => null);

  @override
  Future<({SSHSocket socket, List<SSHClient> jumpClients})> tunnel({
    required SshProxyOptions proxy,
    required SshConnectOptions options,
    required SshProxyHopVerifier onVerifyHostKey,
  }) async {
    throw SshProxyConnectionError(
      'Host key verification for jump host hop0.test:2222 failed',
      null,
      0,
      'hop0.test',
      2222,
    );
  }
}

SshProxyOptions oneHopProxy() => SshProxyOptions(
  hops: const [
    SshProxyHop(host: 'hop0.test', port: 2222, username: 'j0', password: 'jpw'),
  ],
  forwardHost: 'target.test',
  forwardPort: 22,
);

void main() {
  group('SshResourceManager', () {
    test('attachJumpClients registers chain-ordered clients', () {
      final manager = SshResourceManager();
      final hop0 = FakeProxyHopClient();
      final hop1 = FakeProxyHopClient();

      manager.attachJumpClients([hop0, hop1]);

      expect(manager.jumpClients, [hop0, hop1]);
    });

    test('disposeAll closes target, socket, then jumps in reverse', () async {
      final log = <String>[];
      final manager = SshResourceManager();
      final target = LoggedRawClient(log, 'target');
      final socket = FakeSocket();
      final jump0 = LoggedHopClient(log, 'jump0');
      final jump1 = LoggedHopClient(log, 'jump1');

      manager.attachConnection(socket: socket, client: target);
      manager.attachJumpClients([jump0, jump1]);
      await manager.disposeAll();

      expect(log, ['target', 'jump1', 'jump0'], reason: '後ろから close（MR-2）');
      expect(socket.closed, isTrue);
      expect(jump0.closed, isTrue);
      expect(jump1.closed, isTrue);
      expect(manager.jumpClients, isEmpty);
    });

    test(
      'M5: attach is before auth wait — target auth failure still closes jumps',
      () async {
        final hopClients = <BrokenForwardHopClient>[];
        final tunneler = SshProxyTunneler(
          l10n: () => null,
          socketDialer: (host, port, {timeout}) async => FakeSocket(),
          hopClientFactory:
              (
                socket,
                hop, {
                required handshakeTimeout,
                required onAuthenticated,
                required onVerifyHostKey,
              }) async {
                final client = BrokenForwardHopClient();
                hopClients.add(client);
                client.completeAuthentication();
                return client;
              },
        );
        final client = SshClient(proxyTunneler: tunneler);

        // target の転送チャネルが即座に死ぬ → target 認証失敗
        // （SSHAuthAbortError は facade の既存 catch で SshConnectionError に
        // wrap される。型の分岐は既存挙動のまま・ここでの検証対象は資源掃除）
        await expectLater(
          client.connect(
            host: 'target.test',
            port: 22,
            username: 'user',
            options: SshConnectOptions(password: 'pw', proxy: oneHopProxy()),
          ),
          throwsA(isA<SshConnectionError>()),
        );

        // attachJumpClients が認証待ち前に行われているため、
        // _cleanup → disposeAll が jump を閉じられる
        expect(hopClients, hasLength(1));
        expect(hopClients.single.closed, isTrue);
        // keepalive 解決も認証待ち前に適用されている（1 hop 自動 = 10 + 5）
        expect(client.keepAliveProbeTimeoutSeconds, 15);
        await client.dispose();
      },
    );

    test('facade は SshProxyConnectionError の hop 座標付きメッセージを透過する', () async {
      final client = SshClient(proxyTunneler: ThrowingTunneler());

      await expectLater(
        client.connect(
          host: 'target.test',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw', proxy: oneHopProxy()),
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Host key verification for jump host hop0.test:2222 failed',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0)
              .having((e) => e.hopHost, 'hopHost', 'hop0.test')
              .having((e) => e.hopPort, 'hopPort', 2222),
        ),
      );

      // wrap 前メッセージが lastError へ（最終表示メッセージ・H1）
      expect(
        client.lastError,
        'Host key verification for jump host hop0.test:2222 failed',
      );
      await client.dispose();
    });
  });
}
