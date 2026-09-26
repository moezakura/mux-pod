import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'helpers/ssh_client_fakes.dart';

void main() {
  group('SshClient lifecycle contracts', () {
    test(
      'SSH-020/024: connect exposes options and emits connection states',
      () async {
        final rawClient = FakeRawSshClient();
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
        );
        final states = <SshConnectionState>[];
        final subscription = client.connectionStateStream.listen(states.add);
        addTearDown(subscription.cancel);
        final options = SshConnectOptions(
          password: 'pw',
          multiplexer: MultiplexerConfig.tmux('/opt/tmux'),
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: options,
          lightweight: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(identical(client.connectOptions, options), isTrue);
        expect(states, [SshConnectionState.connected]);

        await client.disconnect();
        await Future<void>.delayed(Duration.zero);
        expect(states, [
          SshConnectionState.connected,
          SshConnectionState.disconnected,
        ]);
      },
    );

    test(
      'SSH-LIFE-003/004: input shell restart disposes, recreates, and notifies',
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
        var rebootNotifications = 0;
        client.onInputShellRebooted = () => rebootNotifications++;

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        expect(shells, hasLength(2));
        expect(identical(client.inputShell, shells[1]), isTrue);
        expect(rebootNotifications, 1);

        await client.restartInputShell();

        expect(shells[1].disposed, isTrue);
        expect(shells, hasLength(3));
        expect(identical(client.inputShell, shells[2]), isTrue);
        expect(rebootNotifications, 2);
        await client.disconnect();
      },
    );

    test(
      'SSH-LIFE-008..012: keepalive schedules, adapts, fails, and is cancelled',
      () async {
        final rawClient = FakeRawSshClient();
        final socket = FakeSocket();
        final shells = <FakePersistentShell>[];
        final timers = <FakeTimer>[];
        Object? reportedError;
        var closeCalls = 0;
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: socket, client: rawClient);
          },
          persistentShellFactory: (raw) async {
            final shell = FakePersistentShell(raw);
            shells.add(shell);
            return shell;
          },
          timerFactory: (duration, callback) {
            final timer = FakeTimer(duration, callback);
            timers.add(timer);
            return timer;
          },
        );
        client.setEventHandlers(
          SshEvents(
            onError: (error) => reportedError = error,
            onClose: () => closeCalls++,
          ),
        );

        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
        );

        expect(shells, hasLength(2));
        expect(timers.single.duration, const Duration(seconds: 10));
        for (var i = 0; i < 3; i++) {
          timers.last.fire();
          await Future<void>.delayed(Duration.zero);
        }
        expect(shells.first.commands, ['echo ping', 'echo ping', 'echo ping']);
        expect(timers.last.duration, const Duration(seconds: 15));

        // A lost probe must NOT tear the session down on its own: on a mobile
        // link single misses are routine, and treating one as a disconnect
        // puts the terminal into a permanent reconnect loop.
        shells.first.error = StateError('lost');
        for (var i = 0; i < 2; i++) {
          timers.last.fire();
          await Future<void>.delayed(Duration.zero);
          expect(client.state, isNot(SshConnectionState.error));
          expect(closeCalls, 0);
        }

        // The third consecutive failure is the disconnect.
        timers.last.fire();
        await Future<void>.delayed(Duration.zero);
        expect(client.state, SshConnectionState.error);
        expect(client.lastError, contains('Connection lost'));
        expect(reportedError, isA<SshConnectionError>());
        expect(closeCalls, 1);
        expect(timers.last.isActive, isFalse);

        await client.disconnect();
        expect(socket.closed, isTrue);
        expect(shells.every((shell) => shell.disposed), isTrue);
      },
    );

    test(
      'SSH-LIFE-013..015: interactive shell forwards data, error, and done',
      () async {
        final rawClient = FakeRawSshClient();
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
        );
        final received = <int>[];
        Object? reportedError;
        var closeCalls = 0;
        client.setEventHandlers(
          SshEvents(
            onData: received.addAll,
            onError: (error) => reportedError = error,
            onClose: () => closeCalls++,
          ),
        );
        await client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        );

        await client.startShell(
          const ShellOptions(term: 'vt100', cols: 132, rows: 43),
        );
        expect(rawClient.lastPty?.type, 'vt100');
        expect(rawClient.lastPty?.width, 132);
        expect(rawClient.lastPty?.height, 43);
        rawClient.interactiveSession.emitData([1, 2, 3]);
        await Future<void>.delayed(Duration.zero);
        expect(received, [1, 2, 3]);

        rawClient.interactiveSession.emitError(StateError('stream failed'));
        await Future<void>.delayed(Duration.zero);
        expect(reportedError, isA<StateError>());
        expect(client.lastError, contains('stream failed'));

        await rawClient.interactiveSession.finish();
        await Future<void>.delayed(Duration.zero);
        expect(client.state, SshConnectionState.disconnected);
        expect(closeCalls, 1);
        await client.disconnect();
      },
    );

    test(
      'SSH-LIFE-018: authenticated callback is accepted before completion',
      () async {
        final rawClient = FakeRawSshClient();
        var callbackInvoked = false;
        final client = SshClient(
          connectionFactory: (_, _, _, _, onAuthenticated, _) async {
            onAuthenticated();
            callbackInvoked = true;
            return (socket: FakeSocket(), client: rawClient);
          },
        );

        final connecting = client.connect(
          host: 'host',
          port: 22,
          username: 'user',
          options: SshConnectOptions(password: 'pw'),
          lightweight: true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(callbackInvoked, isTrue);
        expect(client.state, SshConnectionState.connecting);
        rawClient.authentication.complete();
        await connecting;
        expect(client.state, SshConnectionState.connected);
        await client.disconnect();
      },
    );

    test(
      'Issue #56: proxy・keepalive 上書き値は connectionFactory へ透過される（契約不変回帰）',
      () async {
        final rawClient = FakeRawSshClient();
        SshConnectOptions? received;
        final proxyOptions = SshProxyOptions(
          hops: const [
            SshProxyHop(
              host: 'hop0.test',
              port: 2222,
              username: 'j0',
              password: 'jpw',
            ),
          ],
          forwardHost: 'target.test',
          forwardPort: 22,
        );
        final client = SshClient(
          connectionFactory: (_, _, _, options, onAuthenticated, _) async {
            received = options;
            onAuthenticated();
            rawClient.authentication.complete();
            return (socket: FakeSocket(), client: rawClient);
          },
        );
        final options = SshConnectOptions(
          password: 'pw',
          proxy: proxyOptions,
          keepAliveTimeoutSeconds: 25,
        );

        await client.connect(
          host: 'target.test',
          port: 22,
          username: 'user',
          options: options,
          lightweight: true,
        );

        // factory の型契約は不変のまま、options がそのまま届く
        expect(identical(received, options), isTrue);
        expect(identical(received!.proxy, proxyOptions), isTrue);
        expect(received!.keepAliveTimeoutSeconds, 25);
        await client.disconnect();
      },
    );

    test(
      'Issue #56: 直接接続・未設定時の keepalive probe timeout は 10 のまま（既存不変）',
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
          options: SshConnectOptions(password: 'pw'),
        );

        expect(client.keepAliveProbeTimeoutSeconds, 10);
        await client.disconnect();
      },
    );
  });
}
