// P5: SshConnectionOrchestrator テスト（計画 §L4 テスト10・新規）。
// 責務: 再接続（reconnectConnection）時に 1 回目の connect と同一の
// proxy・keepalive 上書き値付き options が再使用されること。
// private フィールド _lastOptions は参照せず、fake SshClient が再接続時に
// 受け取る options の振る舞いで検証する。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/l10n/app_localizations.dart';
import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/ssh_connection_orchestrator.dart';
import 'package:flutter_muxpod/providers/ssh_state.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

/// connect に渡された options を記録する fake SshClient。
class RecordingSshClient extends SshClient {
  final connects = <SshConnectOptions>[];
  var failNextConnect = false;

  @override
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required SshConnectOptions options,
    bool lightweight = false,
    AppLocalizations? l10n,
  }) async {
    connects.add(options);
    if (failNextConnect) {
      failNextConnect = false;
      throw SshConnectionError('first attempt fails');
    }
  }
}

void main() {
  group('SshConnectionOrchestrator reconnect options (Issue #56)', () {
    test(
      'reconnectConnection reuses the same proxy and keepalive options',
      () async {
        var state = const SshState();
        final first = RecordingSshClient();
        final second = RecordingSshClient();
        // 1 回目の connect は失敗させ、その後の reconnect で 2 台目を使う
        first.failNextConnect = true;
        final created = <RecordingSshClient>[first, second];

        final orchestrator = SshConnectionOrchestrator(
          getState: () => state,
          updateState: (reducer) => state = reducer(state),
          requestReconnect: () async => true,
          shouldScheduleNextAttempt: () => false,
          onLastConnected: (_) {},
          startForeground: (_, _, _) async {},
          stopForeground: () async {},
          clientFactory: () => created.removeAt(0),
        );

        final connection = Connection(
          id: 'c1',
          name: 'Server',
          host: 'target.test',
          port: 22,
          username: 'user',
          createdAt: DateTime(2025, 1, 1),
        );
        final proxy = SshProxyOptions(
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
        final options = SshConnectOptions(
          password: 'pw',
          proxy: proxy,
          keepAliveTimeoutSeconds: 25,
        );

        await orchestrator.connectWithoutShell(connection, options);
        expect(first.connects, hasLength(1));
        expect(first.connects.single.proxy, same(proxy));
        expect(first.connects.single.keepAliveTimeoutSeconds, 25);
        // 1 回目は失敗させる（connectWithoutShell は失敗しても options を
        // キャッシュ済みであることが再接続の前提）

        // 切断検知を擬似的に起こして再接続
        state = state.copyWith(connectionState: SshConnectionState.error);
        orchestrator.onDisconnectDetected?.call();

        final reconnected = await orchestrator.reconnectConnection();
        expect(reconnected, isTrue);
        expect(second.connects, hasLength(1));
        // 再接続でも同一の proxy・keepalive 上書き値付き options が使われる
        expect(identical(second.connects.single, options), isTrue);
        expect(second.connects.single.proxy, same(proxy));
        expect(second.connects.single.keepAliveTimeoutSeconds, 25);
      },
    );
  });
}
