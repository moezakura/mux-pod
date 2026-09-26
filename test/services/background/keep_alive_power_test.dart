import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/ssh/ssh_keep_alive.dart';

class _Client implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'stopping in-flight keepalive ignores completion (failure=$fail)',
      (tester) async {
        final pending = Completer<void>();
        var probes = 0;
        var deaths = 0;
        final keepAlive = SshKeepAlive(
          timerFactory: Timer.new,
          probe: () {
            probes++;
            return pending.future;
          },
          onDead: (_) {
            deaths++;
          },
          isConnected: () => true,
          client: () => _Client(),
          l10n: () => null,
        );
        keepAlive.start();
        await tester.pump(const Duration(seconds: 10));
        expect(probes, 1);
        keepAlive.stop();
        if (fail) {
          pending.completeError(StateError('old socket'));
        } else {
          pending.complete();
        }
        await tester.pump();
        await tester.pump(const Duration(minutes: 2));
        expect(probes, 1);
        expect(deaths, 0);
      },
    );
  }
}
