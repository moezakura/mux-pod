import 'package:flutter_muxpod/providers/connection_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

import 'fake_ssh_client.dart';

/// [SshNotifier] をオーバーライドし、ネットワーク監視や再接続を行わず
/// [FakeSshClient] を返すようにするスタブ。
class FakeSshNotifier extends SshNotifier {
  @override
  SshClient? client;

  FakeSshNotifier({this.client});

  @override
  SshState build() => SshState(
        connectionState: client != null
            ? SshConnectionState.connected
            : SshConnectionState.disconnected,
      );

  @override
  Future<void> connect(
    Connection connection,
    SshConnectOptions options,
  ) async {
    client ??= FakeSshClient();
    state = state.copyWith(connectionState: SshConnectionState.connected);
  }

  @override
  Future<void> connectWithoutShell(
    Connection connection,
    SshConnectOptions options,
  ) async {
    client ??= FakeSshClient();
    state = state.copyWith(connectionState: SshConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    await client?.dispose();
    client = null;
    state = state.copyWith(connectionState: SshConnectionState.disconnected);
  }

  @override
  Future<bool> reconnect() async {
    state = state.copyWith(connectionState: SshConnectionState.disconnected);
    return false;
  }

  @override
  Future<bool> reconnectNow() async => false;
}
