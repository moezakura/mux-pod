// P5: SshProxyTunneler テスト（計画 §L4 テスト3・注入点 MR-6 を使用）。
// (a) 単段 forwardTarget (b) 2 hop 連鎖 (c) 失敗 wrap (d) ホスト鍵拒否 H1
// (e)(f) MR-1 per-hop タイムアウト (g) MR-2 失敗時後ろから close
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/ssh_models.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_connection_error.dart';
import 'package:flutter_muxpod/services/ssh/ssh_proxy_tunneler.dart';

import 'helpers/ssh_client_fakes.dart' show FakeSocket;
import 'helpers/ssh_proxy_fakes.dart';

void main() {
  group('SshProxyTunneler', () {
    final fingerprint = Uint8List.fromList(utf8.encode('SHA256:test'));

    SshProxyOptions proxy({
      int hopCount = 1,
      String forwardHost = 'target.test',
      int forwardPort = 22,
    }) {
      return SshProxyOptions(
        hops: List.generate(
          hopCount,
          (i) => SshProxyHop(host: 'hop$i.test', username: 'u$i'),
        ),
        forwardHost: forwardHost,
        forwardPort: forwardPort,
      );
    }

    /// hop 実装を dartssh2 の意味論に合わせてシミュレートする factory。
    ///
    /// onVerifyHostKey を即座に呼び（トランスポートのホスト鍵検証相当）、
    /// 受理なら authenticated を完了・拒否なら SSHAuthAbortError で失敗させる。
    SshProxyHopClientFactory autoAuthFactory(
      List<FakeProxyHopClient> clients, {
      bool accept = true,
    }) {
      return (
        socket,
        hop, {
        required Duration? handshakeTimeout,
        required void Function() onAuthenticated,
        required Future<bool> Function(String type, Uint8List fingerprint)
        onVerifyHostKey,
      }) async {
        final client = FakeProxyHopClient();
        clients.add(client);
        final accepted = await onVerifyHostKey('ssh-ed25519', fingerprint);
        if (accepted && accept) {
          client.completeAuthentication();
        } else {
          client.failAuthentication(
            SSHAuthAbortError('Hostkey verification failed'),
          );
        }
        return client;
      };
    }

    SshProxyTunneler tunneler({
      SshProxySocketDialer? socketDialer,
      SshProxyHopClientFactory? hopClientFactory,
    }) {
      return SshProxyTunneler(
        l10n: () => null,
        socketDialer:
            socketDialer ?? (host, port, {timeout}) async => FakeSocket(),
        hopClientFactory: hopClientFactory ?? buildHopClient,
      );
    }

    test('(a) 単段: forwardLocal に forwardTarget が渡る', () async {
      final clients = <FakeProxyHopClient>[];
      final tun = tunneler(hopClientFactory: autoAuthFactory(clients));

      final result = await tun.tunnel(
        proxy: proxy(forwardHost: '10.0.0.5', forwardPort: 2222),
        options: SshConnectOptions(password: 'pw', timeout: 5),
        onVerifyHostKey: (hop, type, fp) async => true,
      );

      expect(clients, hasLength(1));
      expect(clients.single.forwarded, [(host: '10.0.0.5', port: 2222)]);
      // forwardLocal の戻り値（SSHForwardChannel は SSHSocket implements 済み）
      expect(result.socket, same(clients.single.lastChannel));
      expect(result.jumpClients, [clients.single]);
    });

    test('(b) 2 hop: チェーン順に連鎖する', () async {
      final clients = <FakeProxyHopClient>[];
      final tun = tunneler(hopClientFactory: autoAuthFactory(clients));

      final result = await tun.tunnel(
        proxy: proxy(hopCount: 2, forwardHost: 'target.test'),
        options: SshConnectOptions(password: 'pw', timeout: 5),
        onVerifyHostKey: (hop, type, fp) async => true,
      );

      expect(clients, hasLength(2));
      // hop0 は hop1 へ、hop1 は target へ転送する
      expect(clients[0].forwarded, [(host: 'hop1.test', port: 22)]);
      expect(clients[1].forwarded, [(host: 'target.test', port: 22)]);
      expect(result.jumpClients, [clients[0], clients[1]]);
    });

    test('(c-1) ダイヤル失敗は hop 座標付きで wrap される', () async {
      final tun = tunneler(
        socketDialer: (host, port, {timeout}) async =>
            throw const SocketException('unreachable'),
      );

      await expectLater(
        tun.tunnel(
          proxy: proxy(),
          options: SshConnectOptions(password: 'pw', timeout: 5),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Failed to connect to jump host hop0.test:22: '
                    'SocketException: unreachable',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0)
              .having((e) => e.hopHost, 'hopHost', 'hop0.test')
              .having((e) => e.hopPort, 'hopPort', 22),
        ),
      );
    });

    test('(c-2) hop 認証失敗は SSHAuthFailError をそのまま再throwしない', () async {
      final clients = <FakeProxyHopClient>[];
      final tun = tunneler(
        hopClientFactory:
            (
              socket,
              hop, {
              required handshakeTimeout,
              required onAuthenticated,
              required onVerifyHostKey,
            }) async {
              final client = FakeProxyHopClient();
              clients.add(client);
              client.failAuthentication(SSHAuthFailError('password rejected'));
              return client;
            },
      );

      await expectLater(
        tun.tunnel(
          proxy: proxy(),
          options: SshConnectOptions(password: 'pw', timeout: 5),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Authentication to jump host hop0.test:22 failed',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0),
        ),
      );
      expect(clients.single.closed, isTrue);
    });

    test('(c-3) forwardLocal 失敗は hop 座標付きで wrap される', () async {
      final clients = <FakeProxyHopClient>[];
      final factory = autoAuthFactory(clients);
      // forwardLocal だけ失敗させる
      final tun = tunneler(
        hopClientFactory:
            (
              socket,
              hop, {
              required handshakeTimeout,
              required onAuthenticated,
              required onVerifyHostKey,
            }) async {
              final client =
                  await factory(
                        socket,
                        hop,
                        handshakeTimeout: handshakeTimeout,
                        onAuthenticated: onAuthenticated,
                        onVerifyHostKey: onVerifyHostKey,
                      )
                      as FakeProxyHopClient;
              client.forwardError = SSHChannelOpenError(
                1,
                'administratively prohibited',
              );
              return client;
            },
      );

      await expectLater(
        tun.tunnel(
          proxy: proxy(forwardHost: 'target.test', forwardPort: 22),
          options: SshConnectOptions(password: 'pw', timeout: 5),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Could not reach target.test:22 via the jump host',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0),
        ),
      );
      expect(clients.single.closed, isTrue);
    });

    test('(c-4) 未分類例外（hopClientFactory throw）は hop 座標付きで wrap される', () async {
      final tun = tunneler(
        hopClientFactory:
            (
              socket,
              hop, {
              required handshakeTimeout,
              required onAuthenticated,
              required onVerifyHostKey,
            }) async {
              throw Exception('handshake setup failed');
            },
      );

      await expectLater(
        tun.tunnel(
          proxy: proxy(),
          options: SshConnectOptions(password: 'pw', timeout: 5),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Unexpected error while connecting through jump host '
                    'hop0.test:22: Exception: handshake setup failed',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0)
              .having((e) => e.hopHost, 'hopHost', 'hop0.test')
              .having((e) => e.hopPort, 'hopPort', 22),
        ),
      );
    });

    test('(c-5) hop[1] の未分類例外（非ホスト鍵拒否 SSHAuthAbortError）は '
        'hop[1] 座標付きで wrap される', () async {
      final clients = <FakeProxyHopClient>[];
      var hopCount = 0;
      final tun = tunneler(
        hopClientFactory:
            (
              socket,
              hop, {
              required handshakeTimeout,
              required onAuthenticated,
              required onVerifyHostKey,
            }) async {
              final index = hopCount++;
              final client = FakeProxyHopClient();
              clients.add(client);
              // 両 hop とも onVerifyHostKey は受理（hostKeyRejected=false のまま）
              await onVerifyHostKey('ssh-ed25519', fingerprint);
              if (index == 0) {
                client.completeAuthentication();
              } else {
                client.failAuthentication(
                  SSHAuthAbortError('Connection closed before authentication'),
                );
              }
              return client;
            },
      );

      await expectLater(
        tun.tunnel(
          proxy: proxy(hopCount: 2),
          options: SshConnectOptions(password: 'pw', timeout: 5),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Unexpected error while connecting through jump host '
                    'hop1.test:22: SSHAuthAbortError'
                    '(Connection closed before authentication)',
              )
              .having((e) => e.hopIndex, 'hopIndex', 1)
              .having((e) => e.hopHost, 'hopHost', 'hop1.test')
              .having((e) => e.hopPort, 'hopPort', 22),
        ),
      );
      expect(clients[0].closed, isTrue);
      expect(clients[1].closed, isTrue);
    });

    test('(d) ホスト鍵拒否は hop 座標付きメッセージに変換される（H1）', () async {
      final clients = <FakeProxyHopClient>[];
      final tun = tunneler(
        hopClientFactory: autoAuthFactory(clients, accept: false),
      );

      // facade は SshProxyConnectionError の message を lastError へ書くため
      // この message が「facade 通過後の最終表示メッセージ」になる
      await expectLater(
        tun.tunnel(
          proxy: proxy(),
          options: SshConnectOptions(
            password: 'pw',
            timeout: 5,
            acceptNewHostKeys: false,
          ),
          onVerifyHostKey: (hop, type, fp) async => false,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Host key verification for jump host hop0.test:22 failed',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0)
              .having((e) => e.hopHost, 'hopHost', 'hop0.test'),
        ),
      );
      expect(clients.single.closed, isTrue);
    });

    test('(e) MR-1: 認証が完了しない hop はタイムアウトして close される', () async {
      final clients = <FakeProxyHopClient>[];

      await expectLater(
        SshProxyTunneler(
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
                // ホスト鍵検証のみ行い、認証完了はさせない
                await onVerifyHostKey('ssh-ed25519', fingerprint);
                final client = FakeProxyHopClient();
                clients.clear();
                clients.add(client);
                return client;
              },
        ).tunnel(
          proxy: proxy(),
          options: SshConnectOptions(password: 'pw', timeout: 1),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Timed out connecting to jump host hop0.test:22',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0),
        ),
      );
      expect(clients.single.closed, isTrue);
    });

    test('(f) MR-1: forwardLocal が完了しない hop はタイムアウトして close される', () async {
      final clients = <FakeProxyHopClient>[];
      final factory = autoAuthFactory(clients);
      final tun = tunneler(
        hopClientFactory:
            (
              socket,
              hop, {
              required handshakeTimeout,
              required onAuthenticated,
              required onVerifyHostKey,
            }) async {
              final client =
                  await factory(
                        socket,
                        hop,
                        handshakeTimeout: handshakeTimeout,
                        onAuthenticated: onAuthenticated,
                        onVerifyHostKey: onVerifyHostKey,
                      )
                      as FakeProxyHopClient;
              client.forwardNeverCompletes = true;
              return client;
            },
      );

      await expectLater(
        tun.tunnel(
          proxy: proxy(),
          options: SshConnectOptions(password: 'pw', timeout: 1),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(
          isA<SshProxyConnectionError>()
              .having(
                (e) => e.message,
                'message',
                'Timed out connecting to jump host hop0.test:22',
              )
              .having((e) => e.hopIndex, 'hopIndex', 0),
        ),
      );
      expect(clients.single.closed, isTrue);
    });

    test('(g) MR-2: hop[1] の失敗で hop[0] が後ろから close される', () async {
      final clients = <FakeProxyHopClient>[];
      final sockets = <FakeSocket>[];
      var hopCount = 0;
      final tun = tunneler(
        socketDialer: (host, port, {timeout}) async {
          final socket = FakeSocket();
          sockets.add(socket);
          return socket;
        },
        hopClientFactory:
            (
              socket,
              hop, {
              required handshakeTimeout,
              required onAuthenticated,
              required onVerifyHostKey,
            }) async {
              final index = hopCount++;
              final client = FakeProxyHopClient();
              clients.add(client);
              if (index == 0) {
                // hop[0] は正常に認証まで完了させる
                await onVerifyHostKey('ssh-ed25519', fingerprint);
                client.completeAuthentication();
              } else {
                // hop[1] で認証失敗
                client.failAuthentication(SSHAuthFailError('denied'));
              }
              return client;
            },
      );

      await expectLater(
        tun.tunnel(
          proxy: proxy(hopCount: 2),
          options: SshConnectOptions(password: 'pw', timeout: 5),
          onVerifyHostKey: (hop, type, fp) async => true,
        ),
        throwsA(isA<SshProxyConnectionError>()),
      );

      expect(clients[0].closed, isTrue, reason: 'hop[0] も close される');
      expect(sockets[0].closed, isTrue, reason: 'hop[0] の socket も close される');
      expect(clients[1].closed, isTrue);
    });
  });
}
