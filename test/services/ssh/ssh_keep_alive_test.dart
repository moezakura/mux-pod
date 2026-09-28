// P5: SshKeepAlive テスト（新設・既存 keepalive テストは 0 件のため新規）。
// 責務: 🤝3 keepalive probe タイムアウト解決純関数（T1）と
// probe timeout のインスタンス化・既定 10 秒不変（T4・テスト8）。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/services/ssh/ssh_keep_alive.dart';

import 'helpers/ssh_client_fakes.dart'
    show FakePersistentShell, FakeRawSshClient, FakeSocket, FakeTimer;

void main() {
  group('SshKeepAlive.resolveKeepAliveTimeoutSeconds (🤝3 純関数)', () {
    test('perConnection (接続個別) wins over global and auto', () {
      expect(
        SshKeepAlive.resolveKeepAliveTimeoutSeconds(
          perConnection: 25,
          global: 60,
          proxy: _proxy(2),
        ),
        25,
      );
    });

    test('global (全体設定) wins over auto when perConnection is unset', () {
      expect(
        SshKeepAlive.resolveKeepAliveTimeoutSeconds(
          global: 60,
          proxy: _proxy(2),
        ),
        60,
      );
    });

    test('auto: proxy present is 10 + hops × 5', () {
      expect(SshKeepAlive.resolveKeepAliveTimeoutSeconds(proxy: _proxy(1)), 15);
      expect(SshKeepAlive.resolveKeepAliveTimeoutSeconds(proxy: _proxy(2)), 20);
      expect(SshKeepAlive.resolveKeepAliveTimeoutSeconds(proxy: _proxy(5)), 35);
    });

    test(
      'auto: proxy absent and unset is 10 (existing direct-connection behavior)',
      () {
        expect(SshKeepAlive.resolveKeepAliveTimeoutSeconds(), 10);
      },
    );
  });

  group('SshKeepAlive probe timeout instance (🤝3・テスト8)', () {
    SshKeepAlive buildKeepAlive() {
      return SshKeepAlive(
        timerFactory: (duration, callback) => FakeTimer(duration, callback),
        probe: () async {},
        onDead: (_) {},
        isConnected: () => false,
        client: () => null,
        l10n: () => null,
      );
    }

    test('probe timeout default is 10 (現行不変回帰)', () {
      final keepAlive = buildKeepAlive();
      expect(keepAlive.keepAliveProbeTimeoutSeconds, 10);
    });

    test('probe timeout is instance-settable to the resolved value', () {
      final keepAlive = buildKeepAlive();
      keepAlive.keepAliveProbeTimeoutSeconds =
          SshKeepAlive.resolveKeepAliveTimeoutSeconds(proxy: _proxy(2));
      expect(keepAlive.keepAliveProbeTimeoutSeconds, 20);
    });

    test(
      'facade passes the resolved value to the probe (proxy 2 hops・null 上書き値)',
      () async {
        final rawClient = FakeRawSshClient();
        final shells = <FakePersistentShell>[];
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = FakePersistentShell(raw);
            shells.add(shell);
            return shell;
          },
        );
        final options = SshConnectOptions(
          password: 'pw',
          keepAliveTimeoutSeconds: null,
          proxy: SshProxyOptions(
            hops: const [
              SshProxyHop(host: 'a.test', username: 'u', password: 'p'),
              SshProxyHop(host: 'b.test', username: 'u', password: 'p'),
            ],
            forwardHost: 'target.test',
            forwardPort: 22,
          ),
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: options,
        );

        expect(client.keepAliveProbeTimeoutSeconds, 20);
        await client.disconnect();
      },
    );

    test(
      'facade passes the per-connection override to the probe (直接接続・25 秒)',
      () async {
        final rawClient = FakeRawSshClient();
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
          persistentShellFactory: (raw) async => FakePersistentShell(raw),
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(
            password: 'pw',
            keepAliveTimeoutSeconds: 25,
          ),
        );

        expect(client.keepAliveProbeTimeoutSeconds, 25);
        await client.disconnect();
      },
    );
  });
}

SshProxyOptions _proxy(int hopCount) {
  return SshProxyOptions(
    hops: List.generate(
      hopCount,
      (i) => SshProxyHop(host: 'hop$i.test', username: 'u'),
    ),
    forwardHost: 'target.test',
    forwardPort: 22,
  );
}
