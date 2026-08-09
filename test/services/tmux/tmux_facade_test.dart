import 'package:flutter_muxpod/services/tmux/tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_facade.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExecutor implements TmuxCommandExecutor {
  final Map<String, String> outputs;
  final List<String> commands = [];
  final List<List<String>> restoreCalls = [];

  _FakeExecutor(this.outputs);

  @override
  bool get isConnected => true;

  @override
  String? get tmuxPath => null;

  @override
  Future<String> exec(String command, {Duration? timeout}) async {
    commands.add(command);
    for (final entry in outputs.entries) {
      if (command.contains(entry.key)) return entry.value;
    }
    return '';
  }

  @override
  Future<String> execPersistent(String command, {Duration? timeout}) async =>
      exec(command);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    commands.add(command);
    return (stdout: await exec(command), stderr: '', exitCode: 0);
  }

  @override
  void write(String data) {}

  @override
  Future<void> sendKeysCommand(String command) async {}

  @override
  Future<void> setWindowRestoreTrap(List<String> windowTargets) async {}

  @override
  Future<void> restoreWindowsNoWait(List<String> targets) async {
    restoreCalls.add(List<String>.of(targets));
  }
}

void main() {
  group('TmuxFacade', () {
    test('capturePane removes exactly one trailing LF', () async {
      final executor = _FakeExecutor({'capture-pane': 'line1\nline2\n'});

      final content = await tmuxFacade.capturePane(executor, target: '@1');

      expect(content.plainText, 'line1\nline2');
    });

    test('capturePane preserves single trailing LF as empty line', () async {
      final executor = _FakeExecutor({'capture-pane': 'line1\n'});

      final content = await tmuxFacade.capturePane(executor, target: '@1');

      expect(content.plainText, 'line1');
    });

    test(
      'capturePane does not remove LF when output has no trailing LF',
      () async {
        final executor = _FakeExecutor({'capture-pane': 'line1'});

        final content = await tmuxFacade.capturePane(executor, target: '@1');

        expect(content.plainText, 'line1');
      },
    );

    test(
      'selectWindow issues the exact session and window target command',
      () async {
        final executor = _FakeExecutor({});

        await tmuxFacade.selectWindow(executor, 'main session', 3);

        expect(
          executor.commands.first,
          'tmux select-window -t "main session":3',
        );
      },
    );

    test(
      'restoreWindows delegates all app restore targets to no-wait executor',
      () async {
        final executor = _FakeExecutor({});

        await tmuxFacade.restoreWindows(executor, ['@1', '@3']);

        expect(executor.restoreCalls, [
          ['@1', '@3'],
        ]);
        expect(executor.commands, isEmpty);
      },
    );
  });
}
