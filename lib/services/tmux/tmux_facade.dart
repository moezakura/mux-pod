// inventory: TMUX-FACADE-000
/// tmux 完全契約の Tmux-only 実装
///
/// [TmuxCommandExecutor]（将来は Herdr 等の backend 実装も）を transport として使用する。
library;

import 'dart:async';

import '../command/command_request.dart';
import 'tmux_command_builder.dart';
import 'tmux_command_executor.dart';
import 'tmux_contract.dart';
import 'tmux_models.dart';
import 'tmux_parser_adapter.dart';
import 'tmux_version.dart';

export 'ssh_tmux_command_executor.dart';

// inventory: TMUX-FACADE-001
final TmuxContract tmuxFacade = TmuxFacade();

// inventory: TMUX-FACADE-002
class TmuxFacade implements TmuxContract {
  @override
  List<TmuxSession> parseSessions(String output) =>
      TmuxParser.parseSessions(output);
  @override
  List<TmuxSession> parseFullTree(String output) =>
      TmuxParser.parseFullTree(output);
  @override
  TmuxPaneContent parsePaneContent(
    String output, {
    int? width,
    int? height,
    bool stripTrailingEmptyLines = true,
  }) => TmuxParser.parsePaneContent(
    output,
    width: width,
    height: height,
    stripTrailingEmptyLines: stripTrailingEmptyLines,
  );
  @override
  String stripAnsiCodes(String text) => TmuxParser.stripAnsiCodes(text);
  @override
  Future<TmuxVersionInfo?> getVersion(TmuxCommandExecutor executor) async {
    try {
      final output = await _execChecked(executor, TmuxCommands.version());
      return TmuxVersionInfo.parse(output);
    } on TmuxCommandException {
      return null;
    }
  }

  @override
  Future<bool> hasSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    final output = await _execChecked(
      executor,
      TmuxCommands.hasSession(sessionName),
    );
    return output.trim() == '1';
  }

  @override
  Future<List<TmuxSession>> listSessions(TmuxCommandExecutor executor) async {
    final output = await _execChecked(executor, TmuxCommands.listSessions());
    return TmuxParser.parseSessions(output);
  }

  @override
  Future<List<TmuxSession>> listAllPanes(TmuxCommandExecutor executor) async {
    final output = await _execChecked(executor, TmuxCommands.listAllPanes());
    return TmuxParser.parseFullTree(output);
  }

  @override
  Future<void> startServer(TmuxCommandExecutor executor) async {
    await _execChecked(executor, TmuxCommands.startServer());
  }

  @override
  Future<void> createSession(
    TmuxCommandExecutor executor, {
    required String name,
    String? windowName,
    String? startDirectory,
    bool detached = true,
  }) async {
    await _execChecked(
      executor,
      TmuxCommands.newSession(
        name: name,
        windowName: windowName,
        startDirectory: startDirectory,
        detached: detached,
      ),
    );
  }

  @override
  Future<void> attachSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    await _execChecked(executor, TmuxCommands.attachSession(sessionName));
  }

  @override
  Future<void> killSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    await _execChecked(executor, TmuxCommands.killSession(sessionName));
  }

  @override
  Future<void> renameSession(
    TmuxCommandExecutor executor,
    String oldName,
    String newName,
  ) async {
    await _execChecked(executor, TmuxCommands.renameSession(oldName, newName));
  }

  @override
  Future<List<TmuxWindow>> listWindows(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async {
    final output = await _execChecked(
      executor,
      TmuxCommands.listWindows(sessionName),
    );
    return TmuxParser.parseWindows(output);
  }

  @override
  Future<void> createWindow(
    TmuxCommandExecutor executor, {
    required String sessionName,
    String? windowName,
    String? startDirectory,
    bool background = false,
  }) async {
    await _execChecked(
      executor,
      TmuxCommands.newWindow(
        sessionName: sessionName,
        windowName: windowName,
        startDirectory: startDirectory,
        background: background,
      ),
    );
  }

  @override
  Future<void> selectWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) async {
    await _execChecked(
      executor,
      TmuxCommands.selectWindow(sessionName, windowIndex),
    );
  }

  @override
  Future<void> killWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) async {
    await _execChecked(
      executor,
      TmuxCommands.killWindow(sessionName, windowIndex),
    );
  }

  @override
  Future<void> renameWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
    String newName,
  ) async {
    await _execChecked(
      executor,
      TmuxCommands.renameWindow(sessionName, windowIndex, newName),
    );
  }

  @override
  Future<List<TmuxPane>> listPanes(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) async {
    final output = await _execChecked(
      executor,
      TmuxCommands.listPanes(sessionName, windowIndex),
    );
    return TmuxParser.parsePanes(output);
  }

  @override
  Future<void> selectPane(
    TmuxCommandExecutor executor,
    String paneId, {
    String? previousPaneId,
  }) async {
    if (previousPaneId != null && previousPaneId != paneId) {
      await _execChecked(
        executor,
        TmuxCommands.sendKeys(previousPaneId, '\x1b[O', literal: true),
      );
    }
    await _execChecked(executor, TmuxCommands.selectPane(paneId));
    await _execChecked(
      executor,
      TmuxCommands.sendKeys(paneId, '\x1b[I', literal: true),
    );
  }

  @override
  Future<void> splitPane(
    TmuxCommandExecutor executor, {
    required String target,
    required SplitDirection direction,
    String? startDirectory,
    int? percentage,
  }) async {
    final command = direction == SplitDirection.vertical
        ? TmuxCommands.splitWindowVertical(
            target: target,
            startDirectory: startDirectory,
            percentage: percentage,
          )
        : TmuxCommands.splitWindowHorizontal(
            target: target,
            startDirectory: startDirectory,
            percentage: percentage,
          );
    await _execChecked(executor, command);
  }

  @override
  Future<void> killPane(TmuxCommandExecutor executor, String paneId) async {
    await _execChecked(executor, TmuxCommands.killPane(paneId));
  }

  @override
  Future<void> sendKeys(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  }) async {
    await _execChecked(
      executor,
      TmuxCommands.sendKeys(target, keys, literal: literal),
    );
  }

  @override
  Future<void> sendKeysNoWait(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  }) async {
    await executor.sendKeysCommand(
      TmuxCommands.sendKeys(target, keys, literal: literal),
    );
  }

  @override
  Future<void> sendFocusIn(TmuxCommandExecutor executor, String paneId) async {
    await _execChecked(
      executor,
      TmuxCommands.sendKeys(paneId, '\x1b[I', literal: true),
    );
  }

  @override
  Future<void> sendFocusOut(TmuxCommandExecutor executor, String paneId) async {
    await _execChecked(
      executor,
      TmuxCommands.sendKeys(paneId, '\x1b[O', literal: true),
    );
  }

  @override
  Future<void> enterCopyModeNoWait(
    TmuxCommandExecutor executor,
    String target,
  ) async {
    await executor.sendKeysCommand(TmuxCommands.enterCopyMode(target));
  }

  @override
  Future<void> cancelCopyModeNoWait(
    TmuxCommandExecutor executor,
    String target,
  ) async {
    await executor.sendKeysCommand(TmuxCommands.cancelCopyMode(target));
  }

  @override
  Future<void> pasteText(
    TmuxCommandExecutor executor, {
    required String target,
    required String text,
    bool execute = true,
  }) async {
    try {
      await _execChecked(
        executor,
        TmuxCommands.loadBufferAndPaste(target, text),
      );
      if (execute) {
        await _execChecked(executor, TmuxCommands.sendKeys(target, 'Enter'));
      }
    } on TmuxCommandException {
      await _execChecked(
        executor,
        TmuxCommands.loadBufferAndPasteNoBracketed(target, text),
      );
      if (execute) {
        await _execChecked(executor, TmuxCommands.sendKeys(target, 'Enter'));
      }
    }
  }

  @override
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
      await _execChecked(
        executor,
        TmuxCommands.sendKeys(paneId, path, literal: true),
      );
    }
    if (autoEnter) {
      await _execChecked(executor, TmuxCommands.sendKeys(paneId, 'Enter'));
    }
  }

  @override
  Future<TmuxPaneSnapshot> pollPane(
    TmuxCommandExecutor executor, {
    required String target,
    int historyLines = -120,
  }) async {
    final combined =
        '${TmuxCommands.capturePane(target, escapeSequences: true, startLine: historyLines)}; '
        '${TmuxCommands.getCursorPosition(target)}; '
        '${TmuxCommands.getPaneMode(target)}';
    final result = await executor.execute(
      CommandRequest(
        command: combined,
        transport: CommandTransportPreference.persistentPreferred,
        output: CommandOutputRequirement.outputOnly,
      ),
    );
    final output = result.primaryOutput;

    final modeCut = output.lastIndexOf('\n');
    final paneModeOutput = modeCut >= 0 ? output.substring(modeCut + 1) : '';
    final beforeMode = modeCut >= 0 ? output.substring(0, modeCut) : '';
    final curCut = beforeMode.lastIndexOf('\n');
    final cursorOutput = curCut >= 0 ? beforeMode.substring(curCut + 1) : '';
    final contentOutput = curCut >= 0 ? beforeMode.substring(0, curCut) : '';

    var cursorX = 0, cursorY = 0, paneWidth = 0, paneHeight = 0;
    final cursorTrimmed = cursorOutput.trim();
    if (cursorTrimmed.isNotEmpty) {
      final parts = cursorTrimmed.split(',');
      if (parts.length >= 4) {
        cursorX = int.tryParse(parts[0]) ?? 0;
        cursorY = int.tryParse(parts[1]) ?? 0;
        paneWidth = int.tryParse(parts[2]) ?? 0;
        paneHeight = int.tryParse(parts[3]) ?? 0;
      }
    }
    final processedContent = contentOutput.endsWith('\n')
        ? contentOutput.substring(0, contentOutput.length - 1)
        : contentOutput;
    final content = TmuxParser.parsePaneContent(
      processedContent,
      width: paneWidth,
      height: paneHeight,
      stripTrailingEmptyLines: false,
    );
    return TmuxPaneSnapshot(
      content: content,
      cursorX: cursorX,
      cursorY: cursorY,
      paneWidth: paneWidth,
      paneHeight: paneHeight,
      paneMode: paneModeOutput.trim(),
    );
  }

  @override
  Future<TmuxPaneContent> capturePane(
    TmuxCommandExecutor executor, {
    required String target,
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  }) async {
    final output = await _execChecked(
      executor,
      TmuxCommands.capturePane(
        target,
        escapeSequences: escapeSequences,
        startLine: startLine,
        endLine: endLine,
      ),
    );
    final processedOutput = output.endsWith('\n')
        ? output.substring(0, output.length - 1)
        : output;
    return TmuxParser.parsePaneContent(
      processedOutput,
      stripTrailingEmptyLines: false,
    );
  }

  @override
  Future<void> setHistoryLimit(
    TmuxCommandExecutor executor,
    int lines, {
    required String target,
  }) async {
    await _execChecked(
      executor,
      TmuxCommands.setHistoryLimit(lines, target: target),
    );
  }

  @override
  Future<void> resizeWindow(
    TmuxCommandExecutor executor,
    String target, {
    int? cols,
    int? rows,
  }) async {
    await _execChecked(
      executor,
      TmuxCommands.resizeWindow(target, cols: cols, rows: rows),
    );
  }

  @override
  Future<void> resizePane(
    TmuxCommandExecutor executor,
    String paneId, {
    int? cols,
    int? rows,
  }) async {
    await _execChecked(
      executor,
      TmuxCommands.resizePaneToSize(paneId, cols: cols, rows: rows),
    );
  }

  @override
  Future<void> autoResizeWindow(
    TmuxCommandExecutor executor,
    String target,
  ) async {
    await executor.sendKeysCommand(TmuxCommands.resizeWindowAuto(target));
  }

  @override
  Future<void> selectLayout(
    TmuxCommandExecutor executor,
    String target,
    TmuxLayout layout,
  ) async {
    await _execChecked(executor, TmuxCommands.selectLayout(target, layout));
  }

  @override
  Future<void> setWindowRestoreTrap(
    TmuxCommandExecutor executor,
    List<String> targets,
  ) async {
    await executor.setWindowRestoreTrap(targets);
  }

  @override
  Future<void> clearWindowRestoreTrap(TmuxCommandExecutor executor) async {
    await executor.setWindowRestoreTrap([]);
  }

  @override
  Future<void> restoreWindows(
    TmuxCommandExecutor executor,
    List<String> targets,
  ) async {
    await executor.restoreWindowsNoWait(targets);
  }

  // inventory: TMUX-FACADE-CHECK-001
  /// [CommandExecutor.execute] を使ってコマンドを実行し、
  /// 終了コード/標準エラーがあれば [TmuxCommandException] を投げる。
  ///
  /// ephemeral + separatedOutput を要求する（stderr 分離が必要な tmux
  /// mutation / チェック系コマンド。Codex 根本設計レビュー・バグ2 根本対応）。
  Future<String> _execChecked(
    TmuxCommandExecutor executor,
    String command,
  ) async {
    final result = await executor.execute(
      CommandRequest(
        command: command,
        transport: CommandTransportPreference.ephemeralOnly,
        output: CommandOutputRequirement.separatedOutput,
      ),
    );
    if (result.exitCode != 0 || result.stderr.isNotEmpty) {
      throw TmuxCommandException(
        result.stderr.isNotEmpty
            ? result.stderr.trim()
            : 'tmux command failed (exit code: ${result.exitCode})',
      );
    }
    return result.stdout;
  }
}
