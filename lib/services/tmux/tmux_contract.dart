// inventory: TMUX-CONTRACT-000
/// tmux 完全契約
///
/// Tmux サーバーに対する全操作を抽象化した interface。
/// 実装は [TmuxFacade]、transport は [TmuxCommandExecutor]。
library;

import 'dart:async';

import '../connection_error.dart';
import 'tmux_command_builder.dart';
import 'tmux_command_executor.dart';
import 'tmux_delimiters.dart';
import 'tmux_models.dart';
import 'tmux_version.dart';

// inventory: TMUX-CONTRACT-EXC-001
/// tmux コマンド失敗時の例外。
///
/// 旧実装で tmux 操作失敗時に `SshConnectionError` が投げられていたため、
/// 後方互換のため `SshConnectionError` を継承し `on SshConnectionError catch` でも
/// 捕捉できるようにする。表示も `SshConnectionError: <message>` を維持する。
class TmuxCommandException extends SshConnectionError {
  // inventory: TMUX-CONTRACT-EXC-002
  TmuxCommandException(super.message, [super.cause]);
}

// inventory: TMUX-CONTRACT-EXC-003
/// tmux は成功したが、その出力を 1 レコードも解析できなかったときの例外。
///
/// 区切り文字が往路で失われた出力（UTF-8 でないクライアントに tmux が返す
/// `_` 置換など）は、終了コード 0 のまま空リストに解析され、「セッションが
/// 無い」と区別が付かない。既存の `on TmuxCommandException` でも捕捉できる
/// よう、失敗系の例外を継承する。
class TmuxOutputParseException extends TmuxCommandException {
  // inventory: TMUX-CONTRACT-EXC-004
  TmuxOutputParseException(super.message, [super.cause]);
}

// inventory: TMUX-CONTRACT-001
abstract interface class TmuxContract {
  // inventory: TMUX-CONTRACT-PARSE-001
  /// [delimiters] は [output] を生成したコマンドに渡したものを指定する。
  /// 呼び出しごとに生成されるため、既定値は置かない。
  List<TmuxSession> parseSessions(String output, TmuxDelimiters delimiters);
  // inventory: TMUX-CONTRACT-PARSE-002
  List<TmuxSession> parseFullTree(String output, TmuxDelimiters delimiters);
  // inventory: TMUX-CONTRACT-PARSE-003
  TmuxPaneContent parsePaneContent(
    String output, {
    int? width,
    int? height,
    bool stripTrailingEmptyLines = true,
  });
  // inventory: TMUX-CONTRACT-PARSE-004
  String stripAnsiCodes(String text);

  // inventory: TMUX-CONTRACT-VER-001
  Future<TmuxVersionInfo?> getVersion(TmuxCommandExecutor executor);
  // inventory: TMUX-CONTRACT-SES-001
  Future<bool> hasSession(TmuxCommandExecutor executor, String sessionName);
  // inventory: TMUX-CONTRACT-SES-002
  Future<List<TmuxSession>> listSessions(TmuxCommandExecutor executor);
  // inventory: TMUX-CONTRACT-SES-003
  Future<List<TmuxSession>> listAllPanes(TmuxCommandExecutor executor);
  // inventory: TMUX-CONTRACT-SRV-001
  Future<void> startServer(TmuxCommandExecutor executor);

  // inventory: TMUX-CONTRACT-SES-004
  Future<void> createSession(
    TmuxCommandExecutor executor, {
    required String name,
    String? windowName,
    String? startDirectory,
    bool detached = true,
  });
  // inventory: TMUX-CONTRACT-SES-005
  Future<void> attachSession(TmuxCommandExecutor executor, String sessionName);
  // inventory: TMUX-CONTRACT-SES-006
  Future<void> killSession(TmuxCommandExecutor executor, String sessionName);
  // inventory: TMUX-CONTRACT-SES-007
  Future<void> renameSession(
    TmuxCommandExecutor executor,
    String oldName,
    String newName,
  );

  // inventory: TMUX-CONTRACT-WIN-001
  Future<List<TmuxWindow>> listWindows(
    TmuxCommandExecutor executor,
    String sessionName,
  );
  // inventory: TMUX-CONTRACT-WIN-002
  Future<void> createWindow(
    TmuxCommandExecutor executor, {
    required String sessionName,
    String? windowName,
    String? startDirectory,
    bool background = false,
  });
  // inventory: TMUX-CONTRACT-WIN-003
  Future<void> selectWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  );
  // inventory: TMUX-CONTRACT-WIN-004
  Future<void> killWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  );
  // inventory: TMUX-CONTRACT-WIN-005
  Future<void> renameWindow(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
    String newName,
  );

  // inventory: TMUX-CONTRACT-PANE-001
  Future<List<TmuxPane>> listPanes(
    TmuxCommandExecutor executor,
    String sessionName,
    int windowIndex,
  );
  // inventory: TMUX-CONTRACT-PANE-002
  Future<void> selectPane(
    TmuxCommandExecutor executor,
    String paneId, {
    String? previousPaneId,
  });
  // inventory: TMUX-CONTRACT-PANE-003
  Future<void> splitPane(
    TmuxCommandExecutor executor, {
    required String target,
    required SplitDirection direction,
    String? startDirectory,
    int? percentage,
  });
  // inventory: TMUX-CONTRACT-PANE-004
  Future<void> killPane(TmuxCommandExecutor executor, String paneId);

  // inventory: TMUX-CONTRACT-IN-001
  Future<void> sendKeys(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  });
  // inventory: TMUX-CONTRACT-IN-002
  Future<void> sendKeysNoWait(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  });
  // inventory: TMUX-CONTRACT-IN-003
  Future<void> sendFocusIn(TmuxCommandExecutor executor, String paneId);
  // inventory: TMUX-CONTRACT-IN-004
  Future<void> sendFocusOut(TmuxCommandExecutor executor, String paneId);
  // inventory: TMUX-CONTRACT-IN-005
  Future<void> enterCopyModeNoWait(TmuxCommandExecutor executor, String target);
  // inventory: TMUX-CONTRACT-IN-006
  Future<void> cancelCopyModeNoWait(
    TmuxCommandExecutor executor,
    String target,
  );

  // inventory: TMUX-CONTRACT-PASTE-001
  Future<void> pasteText(
    TmuxCommandExecutor executor, {
    required String target,
    required String text,
    bool execute = true,
  });
  // inventory: TMUX-CONTRACT-PASTE-002
  Future<void> sendBracketedPaste(
    TmuxCommandExecutor executor, {
    required String paneId,
    required String path,
    bool autoEnter = false,
    bool bracketedPaste = true,
  });

  // inventory: TMUX-CONTRACT-CONTENT-001
  Future<TmuxPaneSnapshot> pollPane(
    TmuxCommandExecutor executor, {
    required String target,
    int historyLines = -120,
  });
  // inventory: TMUX-CONTRACT-CONTENT-002
  Future<TmuxPaneContent> capturePane(
    TmuxCommandExecutor executor, {
    required String target,
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  });

  // inventory: TMUX-CONTRACT-HIST-001
  Future<void> setHistoryLimit(
    TmuxCommandExecutor executor,
    int lines, {
    required String target,
  });

  // inventory: TMUX-CONTRACT-RESIZE-001
  Future<void> resizeWindow(
    TmuxCommandExecutor executor,
    String target, {
    int? cols,
    int? rows,
  });
  // inventory: TMUX-CONTRACT-RESIZE-002
  Future<void> resizePane(
    TmuxCommandExecutor executor,
    String paneId, {
    int? cols,
    int? rows,
  });
  // inventory: TMUX-CONTRACT-RESIZE-003
  Future<void> autoResizeWindow(TmuxCommandExecutor executor, String target);
  // inventory: TMUX-CONTRACT-LAYOUT-001
  Future<void> selectLayout(
    TmuxCommandExecutor executor,
    String target,
    TmuxLayout layout,
  );

  // inventory: TMUX-CONTRACT-LIFE-001
  Future<void> setWindowRestoreTrap(
    TmuxCommandExecutor executor,
    List<String> targets,
  );
  // inventory: TMUX-CONTRACT-LIFE-002
  Future<void> clearWindowRestoreTrap(TmuxCommandExecutor executor);
  // inventory: TMUX-CONTRACT-LIFE-003
  Future<void> restoreWindows(
    TmuxCommandExecutor executor,
    List<String> targets,
  );
}
