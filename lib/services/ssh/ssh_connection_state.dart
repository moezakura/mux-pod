// inventory: SSH-018
// inventory: SSH-CONNECTION-STATE-000
/// SSH接続状態
enum SshConnectionState {
  // inventory: SSH-CONNECTION-STATE-001
  disconnected,
  // inventory: SSH-CONNECTION-STATE-002
  connecting,
  // inventory: SSH-CONNECTION-STATE-003
  connected,
  // inventory: SSH-CONNECTION-STATE-004
  error,
}
