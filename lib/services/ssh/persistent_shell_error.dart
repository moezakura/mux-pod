// inventory: SHELL-ERR-001
/// PersistentShell のエラー
class PersistentShellError implements Exception {
  // inventory: LEGACY-0057
  final String message;

  PersistentShellError(this.message);

  @override
  // inventory: LEGACY-0058
  String toString() => 'PersistentShellError: $message';
}
