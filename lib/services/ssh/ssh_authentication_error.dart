// inventory: SSH-002
/// SSH認証エラー
class SshAuthenticationError implements Exception {
  // inventory: LEGACY-0128
  final String message;
  // inventory: LEGACY-0129
  final Object? cause;

  SshAuthenticationError(this.message, [this.cause]);

  @override
  // inventory: LEGACY-0130
  String toString() => 'SshAuthenticationError: $message${cause != null ? ' ($cause)' : ''}';
}
