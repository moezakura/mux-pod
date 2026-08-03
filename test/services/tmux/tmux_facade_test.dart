import 'package:flutter_muxpod/services/tmux/tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_facade.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExecutor implements TmuxCommandExecutor {
  final Map<String, String> outputs;

  _FakeExecutor(this.outputs);

  @override
  bool get isConnected => true;

  @override
  String? get tmuxPath => null;

  @override
  Future<String> exec(String command, {Duration? timeout}) async {
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
    return (stdout: await exec(command), stderr: '', exitCode: 0);
  }

  @override
  void write(String data) {}

  @override
  Future<void> sendKeysCommand(String command) async {}

  @override
  Future<void> setWindowRestoreTrap(List<String> windowTargets) async {}

  @override
  Future<void> restoreWindowsNoWait(List<String> targets) async {}
}

void main() {
  group('TmuxFacade', () {
    test('capturePane removes exactly one trailing LF', () async {
      final executor = _FakeExecutor({
        'capture-pane': 'line1\nline2\n',
      });

      final content = await tmuxFacade.capturePane(
        executor,
        target: '@1',
      );

      expect(content.plainText, 'line1\nline2');
    });

    test('capturePane preserves single trailing LF as empty line', () async {
      final executor = _FakeExecutor({
        'capture-pane': 'line1\n',
      });

      final content = await tmuxFacade.capturePane(
        executor,
        target: '@1',
      );

      expect(content.plainText, 'line1');
    });

    test('capturePane does not remove LF when output has no trailing LF', () async {
      final executor = _FakeExecutor({
        'capture-pane': 'line1',
      });

      final content = await tmuxFacade.capturePane(
        executor,
        target: '@1',
      );

      expect(content.plainText, 'line1');
    });
  });
}
