// inventory: TMUX-OUTPUT-VALIDATOR-000
/// tmux コマンド出力の健全性検査とレガシー区切り正規化
library;

import '../tmux_delimiters.dart';

/// tmux 出力の健全性検査とレガシー区切り正規化。
class TmuxOutputValidator {
  // inventory: TMUX-PARSER-001
  /// Delimiters assumed for output that did not come from [TmuxCommands].
  ///
  /// Everything the app itself asks tmux for is parsed with the pair minted
  /// for that call; this default only covers output of unknown provenance,
  /// which historically used the control characters.
  static const TmuxDelimiters defaultDelimiters = TmuxDelimiters.legacy;

  // inventory: TMUX-PARSER-018
  /// tmuxが実行中かチェック（サーバー起動確認）
  static bool isServerRunning(String output) {
    final lower = output.toLowerCase();
    return !lower.contains('no server running') &&
        !lower.contains('error connecting') &&
        !lower.contains('failed to connect') &&
        !lower.contains('command not found') &&
        !lower.contains('no such file or directory') &&
        !lower.contains('permission denied');
  }

  // inventory: TMUX-PARSER-020
  /// Rewrites every spelling of the legacy delimiters into [delimiters].
  ///
  /// MuxPod used to ask tmux for 0x1f/0x1e, and that output reached the app in
  /// three shapes: the raw bytes, and — because tmux <= 3.5a ran command
  /// output through `strvis` — the literal text `\037` / `\x1f`. Records in
  /// any of those shapes still have to parse, so they are folded onto the pair
  /// the current call is using.
  ///
  /// The delimiters MuxPod asks for today are printable and minted per call
  /// (see [TmuxDelimiters]), so nothing here touches them.
  static String normalizeDelimiters(String output, TmuxDelimiters delimiters) {
    return output
        .replaceAll(TmuxDelimiters.legacyField, delimiters.field)
        .replaceAll(TmuxDelimiters.legacyRecord, delimiters.record)
        .replaceAll(r'\x1f', delimiters.field)
        .replaceAll(r'\x1e', delimiters.record)
        .replaceAll(r'\037', delimiters.field)
        .replaceAll(r'\036', delimiters.record);
  }

  // inventory: TMUX-PARSER-022
  /// Whether [output] carried something the record parsers were meant to turn
  /// into at least one record.
  ///
  /// An empty parse result over output that answers `true` here means the
  /// delimiters did not survive the trip — a failure that used to reach the UI
  /// as "no sessions" with exit code 0.
  static bool hasRecordContent(String output) =>
      output.trim().isNotEmpty && isServerRunning(output);

  // inventory: TMUX-PARSER-021
  /// エラーメッセージを抽出
  static String? extractError(String output) {
    final lower = output.toLowerCase();
    if (lower.contains('no server running')) {
      return 'tmux server is not running';
    }
    if (lower.contains('session not found')) {
      return 'Session not found';
    }
    if (lower.contains('window not found')) {
      return 'Window not found';
    }
    if (lower.contains('pane not found') || lower.contains("can't find pane")) {
      return 'Pane not found';
    }
    if (lower.contains('error')) {
      // 最初のエラー行を返す
      for (final line in output.split('\n')) {
        if (line.toLowerCase().contains('error')) {
          return line.trim();
        }
      }
    }
    return null;
  }
}
