// inventory: TMUX-FACADE-000
/// tmux 完全契約の Tmux-only 実装
///
/// [TmuxCommandExecutor]（将来は Herdr 等の backend 実装も）を transport として使用する。
/// 公開面（[TmuxContract] 40メソッド / [tmuxFacade] シングルトン）は不変。
library;

import '../../l10n/app_localizations.dart';
import 'commands/layout.dart';
import 'exec/command_runner.dart';
import 'ops/content_operations.dart';
import 'ops/pane_operations.dart';
import 'ops/session_operations.dart';
import 'ops/window_operations.dart';
import 'parsers/content_parser.dart';
import 'parsers/session_parser.dart';
import 'parsers/tree_parser.dart';
import 'tmux_command_executor.dart';
import 'tmux_contract.dart';
import 'tmux_delimiters.dart';
import 'tmux_models.dart';
import 'tmux_version.dart';

export 'ssh_tmux_command_executor.dart';

// inventory: TMUX-FACADE-001
final TmuxContract tmuxFacade = TmuxFacade();

// inventory: TMUX-FACADE-002
class TmuxFacade implements TmuxContract {
  /// [l10n] は内部の [TmuxCommandRunner] にそのまま渡す。null の場合は
  /// Runner 内で遅延解決（英語フォールバック・テスト互換）される。
  factory TmuxFacade({AppLocalizations? l10n}) {
    final runner = TmuxCommandRunner(l10n: l10n);
    return TmuxFacade._(
      TmuxSessionOperations(runner),
      TmuxWindowOperations(runner),
      TmuxPaneOperations(runner),
      TmuxContentOperations(runner),
    );
  }

  TmuxFacade._(this._sessions, this._windows, this._panes, this._contents);

  final TmuxSessionOperations _sessions;
  final TmuxWindowOperations _windows;
  final TmuxPaneOperations _panes;
  final TmuxContentOperations _contents;

  // ===== パース委譲 =====

  // inventory: TMUX-CONTRACT-PARSE-001
  @override
  List<TmuxSession> parseSessions(String output, TmuxDelimiters delimiters) =>
      TmuxSessionParser.parse(output, delimiters: delimiters);
  // inventory: TMUX-CONTRACT-PARSE-002
  @override
  List<TmuxSession> parseFullTree(String output, TmuxDelimiters delimiters) =>
      TmuxTreeParser.parse(output, delimiters: delimiters);
  // inventory: TMUX-CONTRACT-PARSE-003
  @override
  TmuxPaneContent parsePaneContent(
    String output, {
    int? width,
    int? height,
    bool stripTrailingEmptyLines = true,
  }) => TmuxContentParser.parse(
    output,
    width: width,
    height: height,
    stripTrailingEmptyLines: stripTrailingEmptyLines,
  );
  // inventory: TMUX-CONTRACT-PARSE-004
  @override
  String stripAnsiCodes(String text) => TmuxContentParser.stripAnsi(text);

  // ===== セッション操作 =====

  // inventory: TMUX-CONTRACT-VER-001
  @override
  Future<TmuxVersionInfo?> getVersion(TmuxCommandExecutor executor) =>
      _sessions.getVersion(executor);
  // inventory: TMUX-CONTRACT-SES-001
  @override
  Future<bool> hasSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) async => _sessions.hasSession(executor, sessionName);
  // inventory: TMUX-CONTRACT-SES-002
  @override
  Future<List<TmuxSession>> listSessions(TmuxCommandExecutor executor) =>
      _sessions.listSessions(executor);
  // inventory: TMUX-CONTRACT-SES-003
  @override
  Future<List<TmuxSession>> listAllPanes(TmuxCommandExecutor executor) =>
      _sessions.listAllPanes(executor);
  // inventory: TMUX-CONTRACT-SRV-001
  @override
  Future<void> startServer(TmuxCommandExecutor executor) =>
      _sessions.startServer(executor);
  // inventory: TMUX-CONTRACT-SES-004
  @override
  Future<void> createSession(
    TmuxCommandExecutor executor, {
    required String name,
    String? windowName,
    String? startDirectory,
    bool detached = true,
  }) => _sessions.createSession(
    executor,
    name: name,
    windowName: windowName,
    startDirectory: startDirectory,
    detached: detached,
  );
  // inventory: TMUX-CONTRACT-SES-005
  @override
  Future<void> attachSession(
    TmuxCommandExecutor executor,
    String sessionName,
  ) => _sessions.attachSession(executor, sessionName);
  // inventory: TMUX-CONTRACT-SES-006
  @override
  Future<void> killSession(TmuxCommandExecutor executor, String sessionName) =>
      _sessions.killSession(executor, sessionName);
  // inventory: TMUX-CONTRACT-SES-007
  @override
  Future<void> renameSession(
    TmuxCommandExecutor executor,
    String oldName,
    String newName,
  ) => _sessions.renameSession(executor, oldName, newName);

  // ===== ウィンドウ操作 =====

  // inventory: TMUX-CONTRACT-WIN-001
  @override
  Future<List<TmuxWindow>> listWindows(
    TmuxCommandExecutor executor,
    String sessionName,
  ) => _windows.listWindows(executor, sessionName);
  // inventory: TMUX-CONTRACT-WIN-002
  @override
  Future<void> createWindow(
    TmuxCommandExecutor executor, {
    required String sessionName,
    String? windowName,
    String? startDirectory,
    bool background = false,
  }) => _windows.createWindow(
    executor,
    sessionName: sessionName,
    windowName: windowName,
    startDirectory: startDirectory,
    background: background,
  );
  // inventory: TMUX-CONTRACT-WIN-003
  @override
  Future<void> selectWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) => _windows.selectWindow(executor, sessionName, windowIndex);
  // inventory: TMUX-CONTRACT-WIN-004
  @override
  Future<void> killWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) => _windows.killWindow(executor, sessionName, windowIndex);
  // inventory: TMUX-CONTRACT-WIN-005
  @override
  Future<void> renameWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
    String newName,
  ) => _windows.renameWindow(executor, sessionName, windowIndex, newName);

  // ===== ペイン操作 =====

  // inventory: TMUX-CONTRACT-PANE-001
  @override
  Future<List<TmuxPane>> listPanes(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  ) => _panes.listPanes(executor, sessionName, windowIndex);
  // inventory: TMUX-CONTRACT-PANE-002
  @override
  Future<void> selectPane(
    TmuxCommandExecutor executor,
    String paneId, {
    String? previousPaneId,
  }) => _panes.selectPane(executor, paneId, previousPaneId: previousPaneId);
  // inventory: TMUX-CONTRACT-PANE-003
  @override
  Future<void> splitPane(
    TmuxCommandExecutor executor, {
    required String target,
    required SplitDirection direction,
    String? startDirectory,
    int? percentage,
  }) => _panes.splitPane(
    executor,
    target: target,
    direction: direction,
    startDirectory: startDirectory,
    percentage: percentage,
  );
  // inventory: TMUX-CONTRACT-PANE-004
  @override
  Future<void> killPane(TmuxCommandExecutor executor, String paneId) =>
      _panes.killPane(executor, paneId);

  // ===== 入力操作 =====

  // inventory: TMUX-CONTRACT-IN-001
  @override
  Future<void> sendKeys(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  }) => _panes.sendKeys(executor, target, keys, literal: literal);
  // inventory: TMUX-CONTRACT-IN-002
  @override
  Future<void> sendKeysNoWait(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  }) => _panes.sendKeysNoWait(executor, target, keys, literal: literal);
  // inventory: TMUX-CONTRACT-IN-003
  @override
  Future<void> sendFocusIn(TmuxCommandExecutor executor, String paneId) =>
      _panes.sendFocusIn(executor, paneId);
  // inventory: TMUX-CONTRACT-IN-004
  @override
  Future<void> sendFocusOut(TmuxCommandExecutor executor, String paneId) =>
      _panes.sendFocusOut(executor, paneId);
  // inventory: TMUX-CONTRACT-IN-005
  @override
  Future<void> enterCopyModeNoWait(
    TmuxCommandExecutor executor,
    String target,
  ) => _panes.enterCopyModeNoWait(executor, target);
  // inventory: TMUX-CONTRACT-IN-006
  @override
  Future<void> cancelCopyModeNoWait(
    TmuxCommandExecutor executor,
    String target,
  ) => _panes.cancelCopyModeNoWait(executor, target);

  // ===== ペースト操作 =====

  // inventory: TMUX-CONTRACT-PASTE-001
  @override
  Future<void> pasteText(
    TmuxCommandExecutor executor, {
    required String target,
    required String text,
    bool execute = true,
  }) =>
      _panes.pasteText(executor, target: target, text: text, execute: execute);
  // inventory: TMUX-CONTRACT-PASTE-002
  @override
  Future<void> sendBracketedPaste(
    TmuxCommandExecutor executor, {
    required String paneId,
    required String path,
    bool autoEnter = false,
    bool bracketedPaste = true,
  }) => _panes.sendBracketedPaste(
    executor,
    paneId: paneId,
    path: path,
    autoEnter: autoEnter,
    bracketedPaste: bracketedPaste,
  );

  // ===== コンテンツ操作 =====

  // inventory: TMUX-CONTRACT-CONTENT-001
  @override
  Future<TmuxPaneSnapshot> pollPane(
    TmuxCommandExecutor executor, {
    required String target,
    int historyLines = -120,
  }) =>
      _contents.pollPane(executor, target: target, historyLines: historyLines);
  // inventory: TMUX-CONTRACT-CONTENT-002
  @override
  Future<TmuxPaneContent> capturePane(
    TmuxCommandExecutor executor, {
    required String target,
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  }) => _contents.capturePane(
    executor,
    target: target,
    startLine: startLine,
    endLine: endLine,
    escapeSequences: escapeSequences,
  );

  // ===== 履歴 =====

  // inventory: TMUX-CONTRACT-HIST-001
  @override
  Future<void> setHistoryLimit(
    TmuxCommandExecutor executor,
    int lines, {
    required String target,
  }) => _contents.setHistoryLimit(executor, lines, target: target);

  // ===== リサイズ・レイアウト =====

  // inventory: TMUX-CONTRACT-RESIZE-001
  @override
  Future<void> resizeWindow(
    TmuxCommandExecutor executor,
    String target, {
    int? cols,
    int? rows,
  }) => _windows.resizeWindow(executor, target, cols: cols, rows: rows);
  // inventory: TMUX-CONTRACT-RESIZE-002
  @override
  Future<void> resizePane(
    TmuxCommandExecutor executor,
    String paneId, {
    int? cols,
    int? rows,
  }) => _panes.resizePane(executor, paneId, cols: cols, rows: rows);
  // inventory: TMUX-CONTRACT-RESIZE-003
  @override
  Future<void> autoResizeWindow(TmuxCommandExecutor executor, String target) =>
      _windows.autoResizeWindow(executor, target);
  // inventory: TMUX-CONTRACT-LAYOUT-001
  @override
  Future<void> selectLayout(
    TmuxCommandExecutor executor,
    String target,
    TmuxLayout layout,
  ) => _windows.selectLayout(executor, target, layout);

  // ===== ライフサイクル =====

  // inventory: TMUX-CONTRACT-LIFE-001
  @override
  Future<void> setWindowRestoreTrap(
    TmuxCommandExecutor executor,
    List<String> targets,
  ) => _windows.setWindowRestoreTrap(executor, targets);
  // inventory: TMUX-CONTRACT-LIFE-002
  @override
  Future<void> clearWindowRestoreTrap(TmuxCommandExecutor executor) =>
      _windows.clearWindowRestoreTrap(executor);
  // inventory: TMUX-CONTRACT-LIFE-003
  @override
  Future<void> restoreWindows(
    TmuxCommandExecutor executor,
    List<String> targets,
  ) => _windows.restoreWindows(executor, targets);
}
