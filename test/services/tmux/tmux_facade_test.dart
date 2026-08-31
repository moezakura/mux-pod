import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/command/command_result.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_contract.dart';
import 'package:flutter_muxpod/services/tmux/tmux_delimiters.dart';
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
  Future<CommandResult> execute(CommandRequest request) async {
    commands.add(request.command);
    final stdout =
        outputs.entries
            .where((e) => request.command.contains(e.key))
            .map((e) => e.value)
            .firstOrNull ??
        '';
    return CommandResult(
      stdout: stdout,
      stderr: '',
      exitCode: 0,
      outputSeparation: CommandOutputSeparation.separated,
      actualTransport: CommandTransport.ephemeral,
    );
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

/// A tmux that answers in exactly the `-F` format it was handed, so a round
/// trip is exercised with the delimiters the facade minted for that call —
/// which no test can know in advance.
class _FormatEchoExecutor implements TmuxCommandExecutor {
  /// Field values per record, in the order the format asks for them.
  final List<List<String>> records;
  final List<String> commands = [];

  _FormatEchoExecutor(this.records);

  @override
  bool get isConnected => true;

  @override
  String? get tmuxPath => null;

  @override
  Future<CommandResult> execute(CommandRequest request) async {
    commands.add(request.command);
    final format = RegExp(
      r'-F "([^"]*)"',
    ).firstMatch(request.command)?.group(1);
    final out = StringBuffer();
    if (format != null) {
      for (final values in records) {
        var i = 0;
        out.write(
          format.replaceAllMapped(RegExp(r'#\{\w+\}'), (_) => values[i++]),
        );
        // tmux ends every -F record with a newline.
        out.write('\n');
      }
    }
    return CommandResult(
      stdout: out.toString(),
      stderr: '',
      exitCode: 0,
      outputSeparation: CommandOutputSeparation.separated,
      actualTransport: CommandTransport.ephemeral,
    );
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

  group('TmuxFacade delimiters', () {
    test(
      'listSessions round-trips the delimiters minted for that call',
      () async {
        // The builder and the parser agree on a pair nobody else has seen; if
        // they ever drift, every record parses to a single field and the list
        // comes back empty with no error at all.
        final executor = _FormatEchoExecutor([
          ['mysession', '1735689600', '1', '3', r'$0'],
          ['other', '1735689700', '0', '1', r'$1'],
        ]);

        final sessions = await tmuxFacade.listSessions(executor);

        expect(sessions.map((s) => s.name), ['mysession', 'other']);
        expect(sessions.first.windowCount, 3);
        expect(sessions.first.attached, isTrue);
      },
    );

    test('a session named after a delimiter is not a delimiter', () async {
      // tmux takes these strings in a session name, so a fixed delimiter can
      // be typed into one and shift the fields of the record around it.
      final foreign = TmuxDelimiters.random();
      final name = '@@F@@${foreign.field}@@R@@';
      final executor = _FormatEchoExecutor([
        [name, '1735689600', '1', '3', r'$0'],
      ]);

      final sessions = await tmuxFacade.listSessions(executor);

      expect(sessions.single.name, name);
      expect(sessions.single.windowCount, 3);
    });

    test('listAllPanes round-trips the minted delimiters', () async {
      final executor = _FormatEchoExecutor([
        [
          'mysession', r'$0', '0', '@0', 'shell', '1', //
          '0', '%0', '1', '80', '24', '0', '0', //
          'title', 'bash', '5', '10', '/home/user', '-',
        ],
      ]);

      final sessions = await tmuxFacade.listAllPanes(executor);

      expect(sessions.single.name, 'mysession');
      expect(sessions.single.windows.single.panes.single.id, '%0');
    });

    test('mangled output is reported, not served as an empty list', () async {
      // What tmux answers a non-UTF-8 client when the delimiters are control
      // characters: every one of them rewritten to '_', exit code 0, empty
      // stderr. Before, that reached the UI as "no tmux sessions found".
      final executor = _FakeExecutor({
        'list-sessions': 'claude/monoroll_\$0\n',
      });

      await expectLater(
        tmuxFacade.listSessions(executor),
        throwsA(isA<TmuxOutputParseException>()),
      );
    });

    test('nothing to parse is an empty list, not a failure', () async {
      final executor = _FakeExecutor({'list-sessions': ''});

      expect(await tmuxFacade.listSessions(executor), isEmpty);
    });

    test('a dead tmux server is an empty list, not a failure', () async {
      final executor = _FakeExecutor({
        'list-sessions': 'no server running on /tmp/tmux-1000/default\n',
      });

      expect(await tmuxFacade.listSessions(executor), isEmpty);
    });
  });
}
