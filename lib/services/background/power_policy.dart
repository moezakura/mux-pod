/// Persisted mode names are independent of translated labels and enum order.
enum BackgroundMode {
  connection,
  balanced,
  powerSaving;

  static BackgroundMode parse(Object? value, BackgroundMode fallback) =>
      values.where((mode) => mode.name == value).firstOrNull ?? fallback;
}

enum NetworkKind { mobile, wifi, unknown }

class PowerDecision {
  const PowerDecision({
    required this.maintainConnection,
    required this.holdCpu,
    required this.holdWifi,
    this.remainingGrace,
  });
  final bool maintainConnection;
  final bool holdCpu;
  final bool holdWifi;
  final Duration? remainingGrace;
}

/// No I/O: the deadline belongs to the background episode, not the network.
PowerDecision decidePower({
  required bool foreground,
  required bool online,
  required bool connectedOrConnecting,
  required bool transferring,
  required BackgroundMode mode,
  required NetworkKind network,
  required Duration backgroundElapsed,
  Duration grace = const Duration(minutes: 1),
}) {
  final remaining = grace - backgroundElapsed;
  final inGrace = mode == BackgroundMode.balanced && remaining > Duration.zero;
  final maintain =
      online &&
      (foreground ||
          transferring ||
          mode == BackgroundMode.connection ||
          inGrace);
  final hold =
      online &&
      (transferring || (!foreground && maintain && connectedOrConnecting));
  return PowerDecision(
    maintainConnection: maintain,
    holdCpu: hold,
    holdWifi: hold && network == NetworkKind.wifi,
    remainingGrace: !foreground && inGrace ? remaining : null,
  );
}
