// inventory: TMUX-PANE-OPS-000
/// ペイン領域のドメイン操作
///
/// selectPane のフォーカス順序（前ペインへ `\x1b[O` → select → `\x1b[I`）、
/// pasteText の bracketed→no-bracketed フォールバック等の不変条件を持つ。
library;

import '../commands/input_commands.dart';
import '../commands/layout.dart';
import '../commands/list_commands.dart';
import '../commands/pane_commands.dart';
import '../exec/command_runner.dart';
import '../parsers/pane_parser.dart';
import '../tmux_command_executor.dart';
import '../tmux_contract.dart';
import '../tmux_delimiters.dart';
import '../tmux_models.dart';

/// ペイン領域のドメイン操作。
class TmuxPaneOperations {
  TmuxPaneOperations(this._runner);

  final TmuxCommandRunner _runner;

  // inventory: TMUX-FACADE-PANE-001
  Future<List<TmuxPane>> listPanes(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) async {
    final delimiters = TmuxDelimiters.random();
    final output = await _runner.run(
      executor,
      TmuxListCommands.panes(sessionName, windowIndex, delimiters),
    );
    return _runner.requireRecords(
      output,
      TmuxPaneParser.parse(output, delimiters: delimiters),
    );
  }

  // inventory: TMUX-FACADE-PANE-002
  Future<void> selectPane(
    TmuxCommandExecutor executor,
    String paneId, {
    String? previousPaneId,
  }) async {
    if (previousPaneId != null && previousPaneId != paneId) {
      await _runner.run(
        executor,
        TmuxInputCommands.sendKeys(previousPaneId, '\x1b[O', literal: true),
      );
    }
    await _runner.run(executor, TmuxPaneCommands.select(paneId));
    await _runner.run(
      executor,
      TmuxInputCommands.sendKeys(paneId, '\x1b[I', literal: true),
    );
  }

  // inventory: TMUX-FACADE-PANE-003
  Future<void> splitPane(
    TmuxCommandExecutor executor, {
    required String target,
    required SplitDirection direction,
    String? startDirectory,
    int? percentage,
  }) async {
    final command = direction == SplitDirection.vertical
        ? TmuxPaneCommands.splitVertical(
            target: target,
            startDirectory: startDirectory,
            percentage: percentage,
          )
        : TmuxPaneCommands.splitHorizontal(
            target: target,
            startDirectory: startDirectory,
            percentage: percentage,
          );
    await _runner.run(executor, command);
  }

  // inventory: TMUX-FACADE-PANE-004
  Future<void> killPane(TmuxCommandExecutor executor, String paneId) async {
    await _runner.run(executor, TmuxPaneCommands.kill(paneId));
  }

  // inventory: TMUX-FACADE-IN-001
  Future<void> sendKeys(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  }) async {
    await _runner.run(
      executor,
      TmuxInputCommands.sendKeys(target, keys, literal: literal),
    );
  }

  // inventory: TMUX-FACADE-IN-002
  Future<void> sendKeysNoWait(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  }) async {
    await executor.sendKeysCommand(
      TmuxInputCommands.sendKeys(target, keys, literal: literal),
    );
  }

  // inventory: TMUX-FACADE-IN-003
  Future<void> sendFocusIn(TmuxCommandExecutor executor, String paneId) async {
    await _runner.run(
      executor,
      TmuxInputCommands.sendKeys(paneId, '\x1b[I', literal: true),
    );
  }

  // inventory: TMUX-FACADE-IN-004
  Future<void> sendFocusOut(TmuxCommandExecutor executor, String paneId) async {
    await _runner.run(
      executor,
      TmuxInputCommands.sendKeys(paneId, '\x1b[O', literal: true),
    );
  }

  // inventory: TMUX-FACADE-IN-005
  Future<void> enterCopyModeNoWait(
    TmuxCommandExecutor executor,
    String target,
  ) async {
    await executor.sendKeysCommand(TmuxInputCommands.enterCopyMode(target));
  }

  // inventory: TMUX-FACADE-IN-006
  Future<void> cancelCopyModeNoWait(
    TmuxCommandExecutor executor,
    String target,
  ) async {
    await executor.sendKeysCommand(TmuxInputCommands.cancelCopyMode(target));
  }

  // inventory: TMUX-FACADE-PASTE-001
  Future<void> pasteText(
    TmuxCommandExecutor executor, {
    required String target,
    required String text,
    bool execute = true,
  }) async {
    try {
      await _runner.run(executor, TmuxInputCommands.paste(target, text));
      if (execute) {
        await _runner.run(
          executor,
          TmuxInputCommands.sendKeys(target, 'Enter'),
        );
      }
    } on TmuxCommandException {
      await _runner.run(
        executor,
        TmuxInputCommands.pasteNoBracketed(target, text),
      );
      if (execute) {
        await _runner.run(
          executor,
          TmuxInputCommands.sendKeys(target, 'Enter'),
        );
      }
    }
  }

  // inventory: TMUX-FACADE-PASTE-002
  Future<void> sendBracketedPaste(
    TmuxCommandExecutor executor, {
    required String paneId,
    required String path,
    bool autoEnter = false,
    bool bracketedPaste = true,
  }) async {
    if (bracketedPaste) {
      executor.write('\x1b[200~$path\x1b[201~');
    } else {
      await _runner.run(
        executor,
        TmuxInputCommands.sendKeys(paneId, path, literal: true),
      );
    }
    if (autoEnter) {
      await _runner.run(executor, TmuxInputCommands.sendKeys(paneId, 'Enter'));
    }
  }

  // inventory: TMUX-FACADE-RESIZE-002
  Future<void> resizePane(
    TmuxCommandExecutor executor,
    String paneId, {
    int? cols,
    int? rows,
  }) async {
    await _runner.run(
      executor,
      TmuxPaneCommands.resizeToSize(paneId, cols: cols, rows: rows),
    );
  }
}
