import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/notification_panes_provider.dart';
import 'package:flutter_muxpod/services/keychain/secure_storage.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_contract.dart';
import 'package:flutter_muxpod/services/tmux/tmux_facade.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';

import '../helpers/fake_ssh_client.dart';

/// 空の接続一覧を提供する stub。
class _EmptyConnectionsNotifier extends ConnectionsNotifier {
  @override
  ConnectionsState build() => const ConnectionsState();
}

class _FixedConnectionsNotifier extends ConnectionsNotifier {
  _FixedConnectionsNotifier(this.connections);

  final List<Connection> connections;

  @override
  ConnectionsState build() => ConnectionsState(connections: connections);
}

class _RecordingSshClient extends FakeSshClient {
  int connectCalls = 0;
  int disconnectCalls = 0;
  String? connectedHost;
  int? connectedPort;
  String? connectedUsername;
  SshConnectOptions? options;

  @override
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required SshConnectOptions options,
    bool lightweight = false,
  }) async {
    connectCalls++;
    connectedHost = host;
    connectedPort = port;
    connectedUsername = username;
    this.options = options;
    setConnected(SshConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    setConnected(SshConnectionState.disconnected);
  }
}

class _FixtureTmuxContract implements TmuxContract {
  _FixtureTmuxContract(this.sessions);

  final List<TmuxSession> sessions;
  final List<TmuxCommandExecutor> listExecutors = [];

  @override
  Future<List<TmuxSession>> listAllPanes(TmuxCommandExecutor executor) async {
    listExecutors.add(executor);
    return sessions;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AlertPane', () {
    test('primaryFlag selects bell over activity', () {
      final pane = AlertPane(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowIndex: 0,
        windowName: 'shell',
        flags: {TmuxWindowFlag.activity, TmuxWindowFlag.bell},
        paneId: '%0',
        paneIndex: 0,
      );
      expect(pane.primaryFlag, TmuxWindowFlag.bell);
    });

    test(
      'primaryFlag orders activity above silence and supports no alert flag',
      () {
        const activity = AlertPane(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'h',
          sessionName: 'main',
          windowIndex: 0,
          windowName: 'shell',
          flags: {TmuxWindowFlag.activity, TmuxWindowFlag.silence},
          paneId: '%0',
          paneIndex: 0,
        );
        const none = AlertPane(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'h',
          sessionName: 'main',
          windowIndex: 0,
          windowName: 'shell',
          flags: {},
          paneId: '%0',
          paneIndex: 0,
        );

        expect(activity.primaryFlag, TmuxWindowFlag.activity);
        expect(none.primaryFlag, isNull);
      },
    );

    test('NOTIF-002/004/005/006/007/010 fields, key, and windowKey', () {
      const pane = AlertPane(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowIndex: 2,
        windowName: 'logs',
        flags: {},
        paneId: '%5',
        paneIndex: 1,
      );
      expect(pane.connectionId, 'c1');
      expect(pane.host, 'h');
      expect(pane.sessionName, 'main');
      expect(pane.windowIndex, 2);
      expect(pane.windowName, 'logs');
      expect(pane.paneIndex, 1);
      expect(pane.key, 'c1:main:2:%5');
      expect(pane.windowKey, 'c1:main:2');
    });
  });

  group('AlertPanesProvider', () {
    setUp(() => SecureStorageService.setTestValues({}));
    tearDown(() => SecureStorageService.setTestValues(null));

    test('initial state is empty', () {
      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(() => _EmptyConnectionsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(alertPanesProvider);
      expect(state.alertPanes, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('dismiss removes alert', () {
      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(() => _EmptyConnectionsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      container.read(alertPanesProvider.notifier).dismiss('c1:main:0:%0');
      expect(container.read(alertPanesProvider).alertPanes, isEmpty);

      // Add and then dismiss
      const pane = AlertPane(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowIndex: 0,
        windowName: 'shell',
        flags: {TmuxWindowFlag.bell},
        paneId: '%0',
        paneIndex: 0,
      );
      container.read(alertPanesProvider.notifier).state = const AlertPanesState(
        alertPanes: [pane],
      );
      container.read(alertPanesProvider.notifier).dismiss(pane.key);
      expect(container.read(alertPanesProvider).alertPanes, isEmpty);
    });

    test(
      'dismiss only clears the selected pane, not its sibling in the window',
      () {
        final container = ProviderContainer(
          overrides: [
            connectionsProvider.overrideWith(() => _EmptyConnectionsNotifier()),
          ],
        );
        addTearDown(container.dispose);
        const first = AlertPane(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'h',
          sessionName: 'main',
          windowIndex: 0,
          windowName: 'shell',
          flags: {TmuxWindowFlag.bell},
          paneId: '%0',
          paneIndex: 0,
        );
        const second = AlertPane(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'h',
          sessionName: 'main',
          windowIndex: 0,
          windowName: 'shell',
          flags: {TmuxWindowFlag.bell},
          paneId: '%1',
          paneIndex: 1,
        );
        container.read(alertPanesProvider.notifier).state =
            const AlertPanesState(alertPanes: [first, second]);

        container.read(alertPanesProvider.notifier).dismiss(first.key);

        expect(container.read(alertPanesProvider).alertPanes, [second]);
      },
    );

    test('refresh with no connections returns empty state', () async {
      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(() => _EmptyConnectionsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(alertPanesProvider.notifier).refresh();
      final state = container.read(alertPanesProvider);
      expect(state.alertPanes, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('clearWindowFlag with missing connection is a no-op', () async {
      final container = ProviderContainer(
        overrides: [
          connectionsProvider.overrideWith(() => _EmptyConnectionsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      const pane = AlertPane(
        connectionId: 'c1',
        connectionName: 'Server',
        host: 'h',
        sessionName: 'main',
        windowIndex: 0,
        windowName: 'shell',
        flags: {TmuxWindowFlag.bell},
        paneId: '%0',
        paneIndex: 0,
      );

      await container.read(alertPanesProvider.notifier).clearWindowFlag(pane);
      // No error and state unchanged.
      expect(container.read(alertPanesProvider).alertPanes, isEmpty);
    });

    test(
      'G1-8a clearWindowFlag connects, emits exact command, and preserves alerts until refresh',
      () async {
        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'server.example',
          port: 2222,
          username: 'alice',
          createdAt: DateTime(2025, 1, 1),
        );
        await SecureStorageService().savePassword('c1', 'pw');
        final sshClient = _RecordingSshClient();
        final container = ProviderContainer(
          overrides: [
            connectionsProvider.overrideWith(
              () => _FixedConnectionsNotifier([connection]),
            ),
            alertPanesProvider.overrideWith(
              () => AlertPanesNotifier(
                sshClient: sshClient,
                tmuxContract: tmuxFacade,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        const selected = AlertPane(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'server.example',
          sessionName: 'main',
          windowIndex: 2,
          windowName: 'alerts',
          flags: {TmuxWindowFlag.bell},
          paneId: '%2',
          paneIndex: 0,
        );
        const sibling = AlertPane(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'server.example',
          sessionName: 'main',
          windowIndex: 2,
          windowName: 'alerts',
          flags: {TmuxWindowFlag.bell},
          paneId: '%3',
          paneIndex: 1,
        );
        const otherWindow = AlertPane(
          connectionId: 'c1',
          connectionName: 'Server',
          host: 'server.example',
          sessionName: 'main',
          windowIndex: 3,
          windowName: 'other',
          flags: {TmuxWindowFlag.activity},
          paneId: '%4',
          paneIndex: 0,
        );
        container.read(alertPanesProvider.notifier).state =
            const AlertPanesState(alertPanes: [selected, sibling, otherWindow]);

        await container
            .read(alertPanesProvider.notifier)
            .clearWindowFlag(selected);

        expect(sshClient.connectCalls, 1);
        expect(sshClient.connectedHost, 'server.example');
        expect(sshClient.connectedPort, 2222);
        expect(sshClient.connectedUsername, 'alice');
        expect(sshClient.options?.password, 'pw');
        expect(
          sshClient.execCommands,
          contains('tmux select-window -t main:2'),
        );
        expect(sshClient.disconnectCalls, 1);
        expect(container.read(alertPanesProvider).alertPanes, [
          selected,
          sibling,
          otherWindow,
        ]);
      },
    );

    test(
      'NOTIF-020/021 refresh with a connection filters flags and builds prioritized pane alerts',
      () async {
        final connection = Connection(
          id: 'c1',
          name: 'Production',
          host: 'prod.example',
          username: 'ops',
          createdAt: DateTime(2025, 1, 1),
        );
        await SecureStorageService().savePassword('c1', 'pw');
        final sshClient = _RecordingSshClient();
        final contract = _FixtureTmuxContract([
          TmuxSession(
            name: 'main',
            windows: [
              TmuxWindow(
                index: 0,
                name: 'alerts',
                flags: {
                  TmuxWindowFlag.current,
                  TmuxWindowFlag.silence,
                  TmuxWindowFlag.activity,
                  TmuxWindowFlag.bell,
                },
                panes: [
                  TmuxPane(index: 0, id: '%0', currentCommand: 'tail'),
                  TmuxPane(index: 1, id: '%1', currentCommand: 'vim'),
                ],
              ),
              TmuxWindow(
                index: 1,
                name: 'quiet',
                flags: {TmuxWindowFlag.current},
                panes: [TmuxPane(index: 0, id: '%2')],
              ),
            ],
          ),
        ]);
        final container = ProviderContainer(
          overrides: [
            connectionsProvider.overrideWith(
              () => _FixedConnectionsNotifier([connection]),
            ),
            alertPanesProvider.overrideWith(
              () => AlertPanesNotifier(
                sshClient: sshClient,
                tmuxContract: contract,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(alertPanesProvider.notifier).refresh();

        final state = container.read(alertPanesProvider);
        expect(state.isLoading, isFalse);
        expect(state.error, isNull);
        expect(state.alertPanes, hasLength(2));
        expect(state.alertPanes.map((pane) => pane.paneId), ['%0', '%1']);
        expect(state.alertPanes.first.flags, {
          TmuxWindowFlag.silence,
          TmuxWindowFlag.activity,
          TmuxWindowFlag.bell,
        });
        expect(state.alertPanes.first.primaryFlag, TmuxWindowFlag.bell);
        expect(state.alertPanes.first.connectionName, 'Production');
        expect(state.alertPanes.first.currentCommand, 'tail');
        expect(contract.listExecutors, [same(sshClient)]);
        expect(sshClient.connectCalls, 1);
        expect(sshClient.disconnectCalls, 1);
      },
    );

    test('AlertPanesState copyWith', () {
      const state = AlertPanesState(isLoading: true);
      final updated = state.copyWith(
        alertPanes: [
          const AlertPane(
            connectionId: 'c1',
            connectionName: 'Server',
            host: 'h',
            sessionName: 'main',
            windowIndex: 0,
            windowName: 'shell',
            flags: {TmuxWindowFlag.bell},
            paneId: '%0',
            paneIndex: 0,
          ),
        ],
      );
      expect(updated.alertPanes, hasLength(1));
      expect(updated.isLoading, isTrue);
    });
  });
}
