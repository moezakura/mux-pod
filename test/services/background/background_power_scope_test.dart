import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/background/background_power_scope.dart';
import 'package:flutter_muxpod/services/background/transfer_activity.dart';
import 'package:flutter_muxpod/services/network/network_monitor.dart';
import '../../helpers/fake_settings_notifier.dart';
import '../../helpers/fake_ssh_notifier.dart';

class _Network extends NetworkMonitor {
  final events =
      StreamController<({NetworkStatus status, NetworkKind kind})>.broadcast();
  NetworkKind currentKind = NetworkKind.wifi;
  @override
  NetworkKind get kind => currentKind;
  @override
  bool get isOnline => true;
  @override
  Stream<({NetworkStatus status, NetworkKind kind})> get changes =>
      events.stream;
  void change(NetworkKind value) {
    currentKind = value;
    events.add((status: NetworkStatus.online, kind: value));
  }
}

class _Ssh extends FakeSshNotifier {
  final maintenance = <bool>[];
  int verifications = 0;
  @override
  void setMaintenanceEnabled(bool enabled) => maintenance.add(enabled);
  @override
  Future<void> verifyOrReconnect() async {
    verifications++;
  }
}

void main() {
  testWidgets('app scope: grace expiry, network switch, transfer and resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final network = _Network();
    final ssh = _Ssh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => FakeSettingsNotifier()),
          sshProvider.overrideWith(() => ssh),
          networkMonitorProvider.overrideWithValue(network),
        ],
        child: BackgroundPowerScope(
          now: tester.binding.clock.now,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    expect(ssh.maintenance.last, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 59));
    expect(ssh.maintenance.last, true);
    network.change(NetworkKind.mobile);
    await tester.pump();
    expect(ssh.maintenance.last, false);
    network.change(NetworkKind.wifi);
    await tester.pump();
    expect(ssh.maintenance.last, true);
    await tester.pump(const Duration(seconds: 1));
    expect(ssh.maintenance.last, false);
    final done = Completer<void>();
    final transfer = TransferActivity.shared.run(() => done.future);
    await tester.pump();
    expect(ssh.maintenance.last, true);
    done.complete();
    await tester.pump();
    await transfer;
    expect(ssh.maintenance.last, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ssh.maintenance.last, true);
    expect(ssh.verifications, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    unawaited(network.events.close());
  });
}
