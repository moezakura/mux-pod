import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';

class _ConnectingNotifier extends SshNotifier {
  _ConnectingNotifier(this.initial);
  final SshState initial;
  @override
  SshState build() => initial;
  @override
  SshClient? get client =>
      throw StateError('must not probe or replace in-flight connection');
}

void main() {
  for (final initial in [
    const SshState(connectionState: SshConnectionState.connecting),
    const SshState(isReconnecting: true),
  ]) {
    test('resume leaves in-flight connection alone ($initial)', () async {
      final container = ProviderContainer(
        overrides: [
          sshProvider.overrideWith(() => _ConnectingNotifier(initial)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sshProvider.notifier).verifyOrReconnect();
    });
  }
}
