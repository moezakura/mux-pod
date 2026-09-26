import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../providers/ssh_provider.dart';
import '../network/network_monitor.dart';
import 'foreground_task_service.dart';
import 'power_policy.dart';
import 'transfer_activity.dart';

/// App-scoped owner: remains active while settings/file-browser routes are open.
class BackgroundPowerScope extends ConsumerStatefulWidget {
  const BackgroundPowerScope({super.key, required this.child, this.now});
  final Widget child;
  final DateTime Function()? now;
  @override
  ConsumerState<BackgroundPowerScope> createState() =>
      _BackgroundPowerScopeState();
}

class _BackgroundPowerScopeState extends ConsumerState<BackgroundPowerScope>
    with WidgetsBindingObserver {
  DateTime? _backgroundSince;
  DateTime _now() => (widget.now ?? DateTime.now)();
  Timer? _deadline;
  StreamSubscription<({NetworkStatus status, NetworkKind kind})>? _network;
  bool _foreground = true;
  bool? _maintenance;
  bool _queued = false;
  bool _verifyOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!_foreground) _backgroundSince = _now();
    ref.listenManual(settingsProvider, (_, _) => _scheduleSync());
    ref.listenManual(sshProvider, (_, _) => _scheduleSync());
    _network = ref
        .read(networkMonitorProvider)
        .changes
        .listen((_) => _scheduleSync());
    TransferActivity.shared.onChanged = _sync;
    _scheduleSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _backgroundSince = null;
      _verifyOnResume = true;
    } else {
      _backgroundSince = _now();
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_queued || !mounted) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (mounted) unawaited(_sync());
    });
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final monitor = ref.read(networkMonitorProvider);
    final settings = ref.read(settingsProvider);
    final ssh = ref.read(sshProvider);
    final decision = decidePower(
      foreground: _foreground,
      online: monitor.isOnline,
      connectedOrConnecting:
          ssh.isConnected || ssh.isConnecting || ssh.isReconnecting,
      transferring: TransferActivity.shared.active,
      mode: settings.backgroundModeFor(monitor.kind),
      network: monitor.kind,
      backgroundElapsed: _backgroundSince == null
          ? Duration.zero
          : _now().difference(_backgroundSince!),
    );
    _deadline?.cancel();
    if (decision.remainingGrace case final remaining?) {
      _deadline = Timer(remaining, _scheduleSync);
    }
    final notifier = ref.read(sshProvider.notifier);
    final wasMaintaining = _maintenance;
    if (_maintenance != decision.maintainConnection) {
      _maintenance = decision.maintainConnection;
      notifier.setMaintenanceEnabled(decision.maintainConnection);
    }
    if (decision.maintainConnection &&
        (_verifyOnResume || (wasMaintaining == false && !ssh.isConnected))) {
      _verifyOnResume = false;
      unawaited(notifier.verifyOrReconnect());
    }
    try {
      await SshForegroundTaskService().setPowerLocks(
        cpu: decision.holdCpu,
        wifi: decision.holdWifi,
      );
    } catch (error, stack) {
      // Power control failure must not replace a transfer's result/cleanup.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'background power',
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadline?.cancel();
    _network?.cancel();
    TransferActivity.shared.onChanged = null;
    unawaited(
      SshForegroundTaskService().setPowerLocks(cpu: false, wifi: false),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
