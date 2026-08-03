// inventory: CONN-ERR-000
// inventory: SSH-001
/// Transport-neutral connection error shared by SSH and other backends.
library;

// inventory: CONN-ERR-001
/// Base exception for connection/transport failures.
///
/// Historically named `SshConnectionError` for backward compatibility; it is
/// used by both SSH concrete layer and tmux contract layer.
class SshConnectionError implements Exception {
  // inventory: CONN-ERR-002
  // inventory: LEGACY-0125
  final String message;
  // inventory: CONN-ERR-003
  // inventory: LEGACY-0126
  final Object? cause;

  SshConnectionError(this.message, [this.cause]);

  @override
  // inventory: CONN-ERR-004
  // inventory: LEGACY-0127
  String toString() => 'SshConnectionError: $message${cause != null ? ' ($cause)' : ''}';
}
