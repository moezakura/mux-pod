import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/session/session_env.dart';
import 'package:flutter_muxpod/screens/terminal/session/session_runtime.dart';

class _Input implements SessionInputPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Env implements SessionEnv {
  @override
  final input = _Input();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('background during a pending poll cannot resurrect the timer', (
    tester,
  ) async {
    final runtime = SessionRuntimeController(_Env());
    final pending = Completer<void>();
    var polls = 0;
    runtime.pollTick = () {
      polls++;
      return pending.future;
    };
    runtime.startPolling();
    await tester.pump(const Duration(milliseconds: 100));
    expect(polls, 1);
    runtime.isInBackground = true;
    runtime.cancelPollTimers();
    pending.complete();
    await tester.pump();
    runtime.startPolling(); // resize/reconnect completion
    runtime.boostPolling();
    await tester.pump(const Duration(minutes: 1));
    expect(polls, 1);
    expect(runtime.pollTimer?.isActive ?? false, false);
    runtime.disposeViewNotifier();
    runtime.disposeLatencyNotifier();
  });

  testWidgets('old completion cannot replace the new foreground schedule', (
    tester,
  ) async {
    final runtime = SessionRuntimeController(_Env());
    final pending = Completer<void>();
    var polls = 0;
    runtime.pollTick = () async {
      polls++;
      if (polls == 1) await pending.future;
    };
    runtime.startPolling();
    await tester.pump(const Duration(milliseconds: 100));
    runtime.isInBackground = true;
    runtime.cancelPollTimers();
    runtime.isInBackground = false;
    runtime.startPolling();
    final newTimer = runtime.pollTimer;
    pending.complete();
    await tester.pump();
    expect(identical(runtime.pollTimer, newTimer), true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(polls, 2);
    runtime.suspendPolling();
    await tester.pump(const Duration(seconds: 10));
    expect(polls, 2);
    runtime.disposeViewNotifier();
    runtime.disposeLatencyNotifier();
  });
}
