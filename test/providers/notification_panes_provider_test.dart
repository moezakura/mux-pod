import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/notification_panes_provider.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';

/// 空の接続一覧を提供する stub。
class _EmptyConnectionsNotifier extends ConnectionsNotifier {
  @override
  ConnectionsState build() => const ConnectionsState();
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

    test('key and windowKey', () {
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
      expect(pane.key, 'c1:main:2:%5');
      expect(pane.windowKey, 'c1:main:2');
    });
  });

  group('AlertPanesProvider', () {
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
      container.read(alertPanesProvider.notifier).state =
          const AlertPanesState(alertPanes: [pane]);
      container.read(alertPanesProvider.notifier).dismiss(pane.key);
      expect(container.read(alertPanesProvider).alertPanes, isEmpty);
    });

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
