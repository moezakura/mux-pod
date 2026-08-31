// inventory: TMUX-FACADE-000
/// tmux 完全契約の Tmux-only 実装
///
/// [TmuxCommandExecutor]（将来は Herdr 等の backend 実装も）を transport として使用する。
library;

import 'dart:async';
import 'dart:math';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_lookup.dart';
import '../command/command_request.dart';
import 'tmux_command_builder.dart';
import 'tmux_command_executor.dart';
import 'tmux_contract.dart';
import 'tmux_delimiters.dart';
import 'tmux_models.dart';
import 'tmux_parser_adapter.dart';
import 'tmux_version.dart';

export 'ssh_tmux_command_executor.dart';

// inventory: TMUX-FACADE-001
final TmuxContract tmuxFacade = TmuxFacade();

/// pollPane セクション区切りマーカーのパターン。
/// コマンド埋め込み時はランダムIDだが、パース側はパターン一致で抽出する
/// （テストfixtureは任意のIDでマーカーを構築できる）。
final RegExp _pollSeparatorPattern = RegExp(r'\x01###POLL_[0-9a-f]+###\x01');

/// pollPane のテスト・本番共通ヘルパ: 区切りマーカー文字列（バイト列版）。
/// [id] には16進文字列を渡す。
String tmuxPollSeparator(String id) => '\x01###POLL_$id###\x01';

// inventory: TMUX-FACADE-002
class TmuxFacade implements TmuxContract {
  /// 任意のローカライズ文字列。null の場合は英語フォールバック（テスト互換）。
  /// グローバルシングルトン [tmuxFacade] は生成時に渡されないため null のまま。
  final AppLocalizations? _l10n;

  TmuxFacade({AppLocalizations? l10n}) : _l10n = l10n;

  /// pollPane 用マーカーID（呼び出しごとにランダム生成）。
  static String _generatePollMarkerId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  List<TmuxSession> parseSessions(String output, TmuxDelimiters delimiters) =>
      TmuxParser.parseSessions(output, delimiters: delimiters);
  @override
  List<TmuxSession> parseFullTree(String output, TmuxDelimiters delimiters) =>
      TmuxParser.parseFullTree(output, delimiters: delimiters);
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
    final delimiters = TmuxDelimiters.random();
    final output = await _execChecked(
      executor,
      TmuxCommands.listSessions(delimiters),
    );
    return _requireRecords(
      output,
      TmuxParser.parseSessions(output, delimiters: delimiters),
    );
  }

  @override
  Future<List<TmuxSession>> listAllPanes(TmuxCommandExecutor executor) async {
    final delimiters = TmuxDelimiters.random();
    final output = await _execChecked(
      executor,
      TmuxCommands.listAllPanes(delimiters),
    );
    return _requireRecords(
      output,
      TmuxParser.parseFullTree(output, delimiters: delimiters),
    );
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
    final delimiters = TmuxDelimiters.random();
    final output = await _execChecked(
      executor,
      TmuxCommands.listWindows(sessionName, delimiters),
    );
    return _requireRecords(
      output,
      TmuxParser.parseWindows(output, delimiters: delimiters),
    );
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
    final delimiters = TmuxDelimiters.random();
    final output = await _execChecked(
      executor,
      TmuxCommands.listPanes(sessionName, windowIndex, delimiters),
    );
    return _requireRecords(
      output,
      TmuxParser.parsePanes(output, delimiters: delimiters),
    );
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
    // セクション区切りマーカー（ランダムID入り）でコンテンツ/カーソル/モードを
    // 正確に区分けする。改行の数で逆から切る方式は、capture-pane 出力の最終行が
    // 空行のときにその改行が「カーソル行との区切り」として消費され、最終空行が
    // ドロップしてキャレット位置が1行上にズレる（Issue #70 のデータ層の原因）。
    // マーカーは \x01（SOH）で挟み、PersistentShell と同じくシェルのエコーバック
    // （リテラル `\x01` 4文字）と実出力（バイト 0x01）を区別できるようにする。
    final markerId = _generatePollMarkerId();
    final printfSep =
        r'\x01###POLL_'
        '$markerId'
        r'###\x01';
    final combined =
        "printf '$printfSep\\n'; "
        '${TmuxCommands.capturePane(target, escapeSequences: true, startLine: historyLines)}; '
        "printf '$printfSep'; "
        '${TmuxCommands.getCursorPosition(target)}; '
        "printf '$printfSep'; "
        '${TmuxCommands.getPaneMode(target)}; '
        "printf '$printfSep'";
    final result = await executor.execute(
      CommandRequest(
        command: combined,
        transport: CommandTransportPreference.persistentPreferred,
        output: CommandOutputRequirement.outputOnly,
      ),
    );
    final output = result.primaryOutput;

    String contentOutput;
    String cursorOutput;
    String paneModeOutput;

    // 出力中の区切りマーカーをパターンマッチで抽出（IDは呼び出しごとにランダム）。
    final sepMatches = _pollSeparatorPattern.allMatches(output).toList();
    if (sepMatches.length >= 3) {
      // マーカー区切り: [\n+capture] [cursor\n] [mode\n]
      // - コンテンツ: 先頭の printf 由来の \n を1つだけ除去し、末尾の capture 最終行の
      //   改行を1つだけ除去する（split の空要素アーティファクト対策。空行は保持される）
      // - cursor/mode: 各セクション末尾の改行を除去
      var capture = output.substring(sepMatches[0].end, sepMatches[1].start);
      if (capture.startsWith('\n')) capture = capture.substring(1);
      if (capture.endsWith('\n')) {
        capture = capture.substring(0, capture.length - 1);
      }
      contentOutput = capture;
      cursorOutput = output
          .substring(sepMatches[1].end, sepMatches[2].start)
          .trimRight();
      var mode = output.substring(sepMatches[2].end, sepMatches[3].start);
      if (mode.startsWith('\n')) mode = mode.substring(1);
      paneModeOutput = mode;
    } else {
      // フォールバック（テストfixture等の非マーカー出力）: 従来の逆方向切割り。
      final modeCut = output.lastIndexOf('\n');
      paneModeOutput = modeCut >= 0 ? output.substring(modeCut + 1) : '';
      final beforeMode = modeCut >= 0 ? output.substring(0, modeCut) : '';
      final curCut = beforeMode.lastIndexOf('\n');
      cursorOutput = curCut >= 0 ? beforeMode.substring(curCut + 1) : '';
      contentOutput = curCut >= 0 ? beforeMode.substring(0, curCut) : '';
    }

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
    final content = TmuxParser.parsePaneContent(
      contentOutput,
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

  /// tmux が出力を返したのに 1 レコードも解析できなかった場合は投げる。
  ///
  /// 区切り文字が往路で失われた出力は終了コード 0 のまま空リストになり、
  /// 「セッションが無い」と見分けが付かないため、成功として返さない。
  List<T> _requireRecords<T>(String output, List<T> records) {
    if (records.isEmpty && TmuxParser.hasRecordContent(output)) {
      throw TmuxOutputParseException(
        (_l10n ?? lookupL10n()).connTmuxOutputUnparsable,
      );
    }
    return records;
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
            : (_l10n ?? lookupL10n()).connTmuxCommandFailed(
                '${result.exitCode}',
              ),
      );
    }
    return result.stdout;
  }
}
