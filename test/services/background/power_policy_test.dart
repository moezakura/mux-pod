import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_persistence.dart';
import 'package:flutter_muxpod/providers/settings_state.dart';
import 'package:flutter_muxpod/services/background/power_policy.dart';
import 'package:flutter_muxpod/services/background/transfer_activity.dart';
import 'package:flutter_muxpod/services/network/network_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PowerDecision decision(
    BackgroundMode mode, {
    int seconds = 0,
    bool foreground = false,
    bool transfer = false,
    bool online = true,
    NetworkKind network = NetworkKind.wifi,
  }) => decidePower(
    foreground: foreground,
    online: online,
    connectedOrConnecting: true,
    transferring: transfer,
    mode: mode,
    network: network,
    backgroundElapsed: Duration(seconds: seconds),
  );

  test('all 27 saved combinations select independently', () {
    for (final mobile in BackgroundMode.values) {
      for (final wifi in BackgroundMode.values) {
        for (final unknown in BackgroundMode.values) {
          final settings = AppSettings(
            mobileBackgroundMode: mobile,
            wifiBackgroundMode: wifi,
            unknownBackgroundMode: unknown,
          );
          expect(settings.backgroundModeFor(NetworkKind.mobile), mobile);
          expect(settings.backgroundModeFor(NetworkKind.wifi), wifi);
          expect(settings.backgroundModeFor(NetworkKind.unknown), unknown);
          expect(
            settings.copyWith(fontSize: 20).unknownBackgroundMode,
            unknown,
          );
        }
      }
    }
  });

  test('balance expires at 60 seconds, not after another network grace', () {
    expect(decision(BackgroundMode.balanced, seconds: 59).holdCpu, true);
    expect(
      decision(BackgroundMode.balanced, seconds: 59).remainingGrace,
      const Duration(seconds: 1),
    );
    for (final network in NetworkKind.values) {
      for (final seconds in [60, 61, 300]) {
        final result = decision(
          BackgroundMode.balanced,
          seconds: seconds,
          network: network,
        );
        expect(result.maintainConnection, false);
        expect(result.holdCpu, false);
        expect(result.remainingGrace, null);
      }
    }
  });

  test('foreground keeps responsiveness without idle locks', () {
    for (final mode in BackgroundMode.values) {
      final result = decision(mode, foreground: true);
      expect(result.maintainConnection, true);
      expect(result.holdCpu, false);
    }
  });

  test('connection priority, transfer exception and offline release', () {
    expect(decision(BackgroundMode.connection, seconds: 3600).holdCpu, true);
    expect(decision(BackgroundMode.powerSaving).maintainConnection, false);
    for (final mode in BackgroundMode.values) {
      expect(decision(mode, transfer: true, seconds: 300).holdCpu, true);
      expect(decision(mode, transfer: true, online: false).holdCpu, false);
      expect(decision(mode, network: NetworkKind.mobile).holdWifi, false);
    }
  });

  test('network classification uses known underlay; VPN-only is unknown', () {
    expect(
      classifyNetwork([ConnectivityResult.wifi, ConnectivityResult.mobile]),
      NetworkKind.wifi,
    );
    expect(classifyNetwork([ConnectivityResult.ethernet]), NetworkKind.wifi);
    expect(
      classifyNetwork([ConnectivityResult.vpn, ConnectivityResult.mobile]),
      NetworkKind.mobile,
    );
    expect(classifyNetwork([ConnectivityResult.vpn]), NetworkKind.unknown);
    expect(classifyNetwork([ConnectivityResult.none]), NetworkKind.unknown);
  });

  test('missing and corrupt saved values use per-network defaults', () async {
    SharedPreferences.setMockInitialValues({
      SettingsPersistence.mobileBackgroundModeKey: 'invalid',
      SettingsPersistence.wifiBackgroundModeKey: 42,
    });
    final settings = await SettingsPersistence().load();
    expect(settings.mobileBackgroundMode, BackgroundMode.powerSaving);
    expect(settings.wifiBackgroundMode, BackgroundMode.balanced);
    expect(settings.unknownBackgroundMode, BackgroundMode.powerSaving);
    final persistence = SettingsPersistence();
    await persistence.save(
      SettingsPersistence.unknownBackgroundModeKey,
      'connection',
    );
    expect(
      (await persistence.load()).unknownBackgroundMode,
      BackgroundMode.connection,
    );
  });

  test(
    'parallel transfer leases last through failure and async cleanup',
    () async {
      final activity = TransferActivity();
      final states = <bool>[];
      activity.onChanged = () async {
        states.add(activity.active);
      };
      final first = Completer<void>();
      final second = Completer<void>();
      final work1 = activity.run(() => first.future);
      final work2 = activity.run(() => second.future);
      expect(activity.active, true);
      first.complete();
      await work1;
      expect(activity.active, true);
      final error = expectLater(work2, throwsStateError);
      second.completeError(StateError('cancelled or failed'));
      await error;
      expect(activity.active, false);
      expect(states, [true, true, true, false]);
    },
  );
}
