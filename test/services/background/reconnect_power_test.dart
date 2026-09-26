import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/ssh_reconnect_policy.dart';
import 'package:flutter_muxpod/providers/ssh_state.dart';
import 'package:flutter_muxpod/services/network/network_monitor.dart';

void main() {
  test(
    'power pause completes cancelled wait and blocks online retry',
    () async {
      var state = const SshState();
      var attempts = 0;
      final policy = SshReconnectPolicy(
        reconnectAction: () async {
          attempts++;
          return true;
        },
        hasLastConnection: () => true,
        getState: () => state,
        updateState: (update) => state = update(state),
      );
      final network = StreamController<NetworkStatus>();
      policy.startNetworkMonitoring(network.stream);
      final pending = policy.reconnect();
      policy.setEnabled(false);
      expect(await pending, false);
      network.add(NetworkStatus.offline);
      await Future<void>.delayed(Duration.zero);
      network.add(NetworkStatus.online);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(attempts, 0);
      expect(await policy.reconnectNow(), false);
      expect(state.isWaitingForNetwork, false);
      policy.setEnabled(true);
      expect(await policy.reconnectNow(), true);
      expect(attempts, 1);
      policy.stop();
      await network.close();
    },
  );
}
