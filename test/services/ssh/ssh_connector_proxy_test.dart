// P5: SshConnector のジャンプ経路テスト（計画 §L4 テスト4）。
// 委譲/現行分岐・validate 拡張（上限5/重複/空 host/不正 port/credential 欠落/
// 転送先 M6）・connectionFactory 経路 jumpClients: const []・
// (h) C1: proxy 経路 target 鍵パース失敗 → hop close・(i) C1: 非 proxy 経路
// 鍵パース失敗 → socket close（既存欠陥同時修正の回帰）。
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/connection_error.dart';
import 'package:flutter_muxpod/services/ssh/ssh_authentication_error.dart';
import 'package:flutter_muxpod/services/ssh/ssh_connector.dart';
import 'package:flutter_muxpod/services/ssh/ssh_models.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_tunneler.dart';

import 'helpers/ssh_client_fakes.dart' show FakeSocket;
import 'helpers/ssh_proxy_fakes.dart';

/// 委譲を記録する fake tunneler。
class RecordingTunneler extends SshProxyTunneler {
  RecordingTunneler() : super(l10n: () => null);

  int calls = 0;
  SshProxyOptions? lastProxy;
  SshConnectOptions? lastOptions;

  @override
  Future<({SSHSocket socket, List<SSHClient> jumpClients})> tunnel({
    required SshProxyOptions proxy,
    required SshConnectOptions options,
    required SshProxyHopVerifier onVerifyHostKey,
  }) async {
    calls++;
    lastProxy = proxy;
    lastOptions = options;
    return (socket: FakeSocket(), jumpClients: <SSHClient>[
      FakeProxyHopClient(),
    ]);
  }
}

void main() {
  group('SshConnector proxy routing (Issue #56)', () {
    final hop = SshProxyHop(
      host: 'hop0.test',
      port: 2222,
      username: 'jump',
      password: 'jpw',
    );

    SshProxyOptions proxy({List<SshProxyHop>? hops, int? forwardPort}) {
      return SshProxyOptions(
        hops: hops ?? [hop],
        forwardHost: '',
        forwardPort: forwardPort ?? 22,
      );
    }

    SshConnector connector({SshProxySocketDialer? socketDialer}) {
      return SshConnector(
        connectionFactory: null,
        l10n: () => null,
        setLastError: (_) {},
        socketDialer: socketDialer ?? (host, port, {timeout}) async {
          throw StateError('unexpected direct dial');
        },
      );
    }

    group('validate (MR-7 / M6)', () {
      void validate(SshProxyOptions proxyOptions) {
        connector().validateConnectionParams(
          'target.test',
          22,
          'user',
          SshConnectOptions(password: 'pw', proxy: proxyOptions),
        );
      }

      test('valid single hop passes', () {
        expect(() => validate(proxy()), returnsNormally);
      });

      test('empty hops is rejected', () {
        expect(
          () => validate(proxy(hops: const [])),
          throwsA(
            isA<SshConnectionError>().having(
              (e) => e.message,
              'message',
              'Jump host chain must not be empty',
            ),
          ),
        );
      });

      test('more than 5 hops is rejected (上限5)', () {
        final hops = List.generate(
          6,
          (i) => SshProxyHop(host: 'hop$i.test', username: 'u', password: 'p'),
        );
        expect(
          () => validate(proxy(hops: hops)),
          throwsA(
            isA<SshConnectionError>().having(
              (e) => e.message,
              'message',
              'Up to 5 hops',
            ),
          ),
        );
      });

      test('duplicate host:port in hops is rejected', () {
        expect(
          () => validate(
            proxy(
              hops: [
                hop,
                SshProxyHop(
                  host: 'HOP0.test',
                  port: 2222,
                  username: 'again',
                  password: 'p',
                ),
              ],
            ),
          ),
          throwsA(
            isA<SshConnectionError>().having(
              (e) => e.message,
              'message',
              'Jump host HOP0.test:2222 is already in the chain',
            ),
          ),
        );
      });

      test('empty hop host is rejected', () {
        expect(
          () => validate(
            proxy(
              hops: [SshProxyHop(host: ' ', username: 'u', password: 'p')],
            ),
          ),
          throwsA(
            isA<SshConnectionError>().having(
              (e) => e.message,
              'message',
              'Host is required',
            ),
          ),
        );
      });

      test('out-of-range hop port is rejected', () {
        expect(
          () => validate(
            proxy(
              hops: [
                SshProxyHop(host: 'h.test', port: 0, username: 'u', password: 'p'),
              ],
            ),
          ),
          throwsA(
            isA<SshConnectionError>().having(
              (e) => e.message,
              'message',
              'Invalid port number: 0',
            ),
          ),
        );
      });

      test('hop without credential is rejected', () {
        expect(
          () => validate(
            proxy(hops: [SshProxyHop(host: 'h.test', username: 'u')]),
          ),
          throwsA(isA<SshAuthenticationError>()),
        );
      });

      test('forwardPort out of range is rejected when forwardHost set (M6)', () {
        expect(
          () => validate(
            SshProxyOptions(
              hops: [hop],
              forwardHost: '10.0.0.5',
              forwardPort: 0,
            ),
          ),
          throwsA(
            isA<SshConnectionError>().having(
              (e) => e.message,
              'message',
              'Invalid port number: 0',
            ),
          ),
        );
      });

      test('forwardPort without forwardHost is ignored (M6)', () {
        expect(
          () => validate(proxy(forwardPort: 99999)),
          returnsNormally,
        );
      });
    });

    test('proxy 経路は tunneler へ委譲し jumpClients を透過する', () async {
      final tunneler = RecordingTunneler();
      final sut = SshConnector(
        connectionFactory: null,
        l10n: () => null,
        setLastError: (_) {},
        tunneler: tunneler,
      );
      final options = SshConnectOptions(password: 'pw', proxy: proxy());

      final result = await sut.connect(
        host: 'target.test',
        port: 22,
        username: 'user',
        options: options,
        onAuthenticated: () {},
      );

      expect(tunneler.calls, 1);
      expect(identical(tunneler.lastProxy, options.proxy), isTrue);
      expect(result.jumpClients, hasLength(1));
      expect(result.jumpClients.single, isA<FakeProxyHopClient>());
    });

    test('現行経路（proxy なし）は直接ダイヤルする', () async {
      final socket = FakeSocket();
      var dials = 0;
      final sut = connector(
        socketDialer: (host, port, {timeout}) async {
          dials++;
          expect(host, 'target.test');
          expect(port, 22);
          expect(timeout, const Duration(seconds: 30));
          return socket;
        },
      );

      final result = await sut.connect(
        host: 'target.test',
        port: 22,
        username: 'user',
        options: SshConnectOptions(password: 'pw'),
        onAuthenticated: () {},
      );

      expect(dials, 1);
      expect(identical(result.socket, socket), isTrue);
      expect(result.jumpClients, isEmpty);
      expect(result.client, isA<SSHClient>());
    });

    test('connectionFactory 経路は jumpClients: const []（契約不変）', () async {
      SshConnectOptions? receivedOptions;
      final sut = SshConnector(
        connectionFactory: (
          host,
          port,
          username,
          options,
          onAuthenticated,
          onVerifyHostKey,
        ) async {
          receivedOptions = options;
          return (socket: FakeSocket(), client: FakeProxyHopClient());
        },
        l10n: () => null,
        setLastError: (_) {},
      );
      final proxyOptions = proxy();
      final options = SshConnectOptions(
        password: 'pw',
        proxy: proxyOptions,
        keepAliveTimeoutSeconds: 20,
      );

      final result = await sut.connect(
        host: 'target.test',
        port: 22,
        username: 'user',
        options: options,
        onAuthenticated: () {},
      );

      expect(identical(receivedOptions, options), isTrue);
      final received = receivedOptions!;
      expect(identical(received.proxy, proxyOptions), isTrue);
      expect(received.keepAliveTimeoutSeconds, 20);
      expect(result.jumpClients, isEmpty);
    });

    test('(h) C1: proxy 経路で target 鍵パース失敗 → hop が close される', () async {
      final clients = <FakeProxyHopClient>[];
      final tunneler = SshProxyTunneler(
        l10n: () => null,
        socketDialer: (host, port, {timeout}) async => FakeSocket(),
        hopClientFactory: (
          socket,
          hop, {
          required handshakeTimeout,
          required onAuthenticated,
          required onVerifyHostKey,
        }) async {
          final client = FakeProxyHopClient();
          clients.add(client);
          client.completeAuthentication();
          return client;
        },
      );
      final sut = SshConnector(
        connectionFactory: null,
        l10n: () => null,
        setLastError: (_) {},
        tunneler: tunneler,
      );

      await expectLater(
        sut.connect(
          host: 'target.test',
          port: 22,
          username: 'user',
          options: SshConnectOptions(
            privateKey: 'not a pem',
            proxy: proxy(),
          ),
          onAuthenticated: () {},
        ),
        throwsA(isA<SshAuthenticationError>()),
      );

      expect(clients, hasLength(1));
      expect(clients.single.closed, isTrue, reason: 'C1: hop[0] close');
    });

    test('(i) C1: 非 proxy 経路で鍵パース失敗 → socket が close される', () async {
      final socket = FakeSocket();
      final sut = connector(
        socketDialer: (host, port, {timeout}) async => socket,
      );

      await expectLater(
        sut.connect(
          host: 'target.test',
          port: 22,
          username: 'user',
          options: SshConnectOptions(privateKey: 'not a pem'),
          onAuthenticated: () {},
        ),
        throwsA(isA<SshAuthenticationError>()),
      );

      expect(socket.closed, isTrue, reason: '既存 socket リーク欠陥の同時修正');
    });
  });
}
