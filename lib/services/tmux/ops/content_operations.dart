// inventory: TMUX-CONTENT-OPS-000
/// ペインコンテンツ取得のドメイン操作
///
/// pollPane のマーカー合成と切り出し、capturePane の末尾改行除去という
/// 不変条件を持つ。
library;

import 'dart:math';

import '../../command/command_request.dart';
import '../commands/content_commands.dart';
import '../exec/command_runner.dart';
import '../parsers/content_parser.dart';
import '../tmux_command_executor.dart';
import '../tmux_models.dart';

/// pollPane セクション区切りマーカーのパターン。
/// コマンド埋め込み時はランダムIDだが、パース側はパターン一致で抽出する
/// （テストfixtureは任意のIDでマーカーを構築できる）。
final RegExp _pollSeparatorPattern = RegExp(r'\x01###POLL_[0-9a-f]+###\x01');

/// pollPane のテスト・本番共通ヘルパ: 区切りマーカー文字列（バイト列版）。
/// [id] には16進文字列を渡す。
String tmuxPollSeparator(String id) => '\x01###POLL_$id###\x01';

/// ペインコンテンツ取得のドメイン操作。
class TmuxContentOperations {
  TmuxContentOperations(this._runner);

  final TmuxCommandRunner _runner;

  /// pollPane 用マーカーID（呼び出しごとにランダム生成）。
  static String _generatePollMarkerId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // inventory: TMUX-FACADE-CONTENT-001
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
        '${TmuxContentCommands.capture(target, escapeSequences: true, startLine: historyLines)}; '
        "printf '$printfSep'; "
        '${TmuxContentCommands.cursorPosition(target)}; '
        "printf '$printfSep'; "
        '${TmuxContentCommands.getMode(target)}; '
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
    final content = TmuxContentParser.parse(
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

  // inventory: TMUX-FACADE-CONTENT-002
  Future<TmuxPaneContent> capturePane(
    TmuxCommandExecutor executor, {
    required String target,
    int? startLine,
    int? endLine,
    bool escapeSequences = true,
  }) async {
    final output = await _runner.run(
      executor,
      TmuxContentCommands.capture(
        target,
        escapeSequences: escapeSequences,
        startLine: startLine,
        endLine: endLine,
      ),
    );
    final processedOutput = output.endsWith('\n')
        ? output.substring(0, output.length - 1)
        : output;
    return TmuxContentParser.parse(
      processedOutput,
      stripTrailingEmptyLines: false,
    );
  }

  // inventory: TMUX-FACADE-HIST-001
  Future<void> setHistoryLimit(
    TmuxCommandExecutor executor,
    int lines, {
    required String target,
  }) async {
    await _runner.run(
      executor,
      TmuxContentCommands.setHistoryLimit(lines, target: target),
    );
  }
}
