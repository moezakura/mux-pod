// inventory: TMUX-WINDOW-OPS-000
/// ウィンドウ領域のドメイン操作
library;

import '../commands/layout.dart';
import '../commands/list_commands.dart';
import '../commands/window_commands.dart';
import '../exec/command_runner.dart';
import '../parsers/window_parser.dart';
import '../tmux_command_executor.dart';
import '../tmux_delimiters.dart';
import '../tmux_models.dart';

/// ウィンドウ領域のドメイン操作。
class TmuxWindowOperations {
  TmuxWindowOperations(this._runner);

  final TmuxCommandRunner _runner;

  // inventory: TMUX-FACADE-WIN-001
  Future<List<TmuxWindow>> listWindows(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    final delimiters = TmuxDelimiters.random();
    final output = await _runner.run(
      executor,
      TmuxListCommands.windows(sessionName, delimiters),
    );
    return _runner.requireRecords(
      output,
      TmuxWindowParser.parse(output, delimiters: delimiters),
    );
  }

  // inventory: TMUX-FACADE-WIN-002
  Future<void> createWindow(
    TmuxCommandExecutor executor, {
    required String sessionName,
    String? windowName,
    String? startDirectory,
    bool background = false,
  }) async {
    await _runner.run(
      executor,
      TmuxWindowCommands.create(
        sessionName: sessionName,
        windowName: windowName,
        startDirectory: startDirectory,
        background: background,
      ),
    );
  }

  // inventory: TMUX-FACADE-WIN-003
  Future<void> selectWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) async {
    await _runner.run(
      executor,
      TmuxWindowCommands.select(sessionName, windowIndex),
    );
  }

  // inventory: TMUX-FACADE-WIN-004
  Future<void> killWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) async {
    await _runner.run(
      executor,
      TmuxWindowCommands.kill(sessionName, windowIndex),
    );
  }

  // inventory: TMUX-FACADE-WIN-005
  Future<void> renameWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
    String newName,
  ) async {
    await _runner.run(
      executor,
      TmuxWindowCommands.rename(sessionName, windowIndex, newName),
    );
  }

  // inventory: TMUX-FACADE-RESIZE-001
  Future<void> resizeWindow(
    TmuxCommandExecutor executor,
    String target, {
    int? cols,
    int? rows,
  }) async {
    await _runner.run(
      executor,
      TmuxWindowCommands.resize(target, cols: cols, rows: rows),
    );
  }

  // inventory: TMUX-FACADE-RESIZE-003
  Future<void> autoResizeWindow(
    TmuxCommandExecutor executor,
    String target,
  ) async {
    await executor.sendKeysCommand(TmuxWindowCommands.resizeAuto(target));
  }

  // inventory: TMUX-FACADE-LAYOUT-001
  Future<void> selectLayout(
    TmuxCommandExecutor executor,
    String target,
    TmuxLayout layout,
  ) async {
    await _runner.run(
      executor,
      TmuxWindowCommands.selectLayout(target, layout),
    );
  }

  // inventory: TMUX-FACADE-LIFE-001
  Future<void> setWindowRestoreTrap(
    TmuxCommandExecutor executor,
    List<String> targets,
  ) async {
    await executor.setWindowRestoreTrap(targets);
  }

  // inventory: TMUX-FACADE-LIFE-002
  Future<void> clearWindowRestoreTrap(TmuxCommandExecutor executor) async {
    await executor.setWindowRestoreTrap([]);
  }

  // inventory: TMUX-FACADE-LIFE-003
  Future<void> restoreWindows(
    TmuxCommandExecutor executor,
    List<String> targets,
  ) async {
    await executor.restoreWindowsNoWait(targets);
  }
}
