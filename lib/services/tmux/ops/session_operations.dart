// inventory: TMUX-SESSION-OPS-000
/// セッション領域のドメイン操作
///
/// コマンド生成→実行→（パース）→検証の順序づけと、
/// delimiters の mint→同一ペア保証・requireRecords 適用という不変条件を持つ。
library;

import '../commands/list_commands.dart';
import '../commands/session_commands.dart';
import '../exec/command_runner.dart';
import '../parsers/session_parser.dart';
import '../parsers/tree_parser.dart';
import '../tmux_command_executor.dart';
import '../tmux_contract.dart';
import '../tmux_delimiters.dart';
import '../tmux_models.dart';
import '../tmux_version.dart';

/// セッション領域のドメイン操作。
class TmuxSessionOperations {
  TmuxSessionOperations(this._runner);

  final TmuxCommandRunner _runner;

  // inventory: TMUX-FACADE-VER-001
  Future<TmuxVersionInfo?> getVersion(TmuxCommandExecutor executor) async {
    try {
      final output = await _runner.run(executor, TmuxSessionCommands.version());
      return TmuxVersionInfo.parse(output);
    } on TmuxCommandException {
      return null;
    }
  }

  // inventory: TMUX-FACADE-SES-001
  Future<bool> hasSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    final output = await _runner.run(
      executor,
      TmuxSessionCommands.has(sessionName),
    );
    return output.trim() == '1';
  }

  // inventory: TMUX-FACADE-SES-002
  Future<List<TmuxSession>> listSessions(TmuxCommandExecutor executor) async {
    final delimiters = TmuxDelimiters.random();
    final output = await _runner.run(
      executor,
      TmuxListCommands.sessions(delimiters),
    );
    return _runner.requireRecords(
      output,
      TmuxSessionParser.parse(output, delimiters: delimiters),
    );
  }

  // inventory: TMUX-FACADE-SES-003
  Future<List<TmuxSession>> listAllPanes(TmuxCommandExecutor executor) async {
    final delimiters = TmuxDelimiters.random();
    final output = await _runner.run(
      executor,
      TmuxListCommands.allPanes(delimiters),
    );
    return _runner.requireRecords(
      output,
      TmuxTreeParser.parse(output, delimiters: delimiters),
    );
  }

  // inventory: TMUX-FACADE-SRV-001
  Future<void> startServer(TmuxCommandExecutor executor) async {
    await _runner.run(executor, TmuxSessionCommands.startServer());
  }

  // inventory: TMUX-FACADE-SES-004
  Future<void> createSession(
    TmuxCommandExecutor executor, {
    required String name,
    String? windowName,
    String? startDirectory,
    bool detached = true,
  }) async {
    await _runner.run(
      executor,
      TmuxSessionCommands.create(
        name: name,
        windowName: windowName,
        startDirectory: startDirectory,
        detached: detached,
      ),
    );
  }

  // inventory: TMUX-FACADE-SES-005
  Future<void> attachSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    await _runner.run(executor, TmuxSessionCommands.attach(sessionName));
  }

  // inventory: TMUX-FACADE-SES-006
  Future<void> killSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    await _runner.run(executor, TmuxSessionCommands.kill(sessionName));
  }

  // inventory: TMUX-FACADE-SES-007
  Future<void> renameSession(
    TmuxCommandExecutor executor,
    String oldName,
    String newName,
  ) async {
    await _runner.run(executor, TmuxSessionCommands.rename(oldName, newName));
  }
}
