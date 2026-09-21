// inventory: TMUX-WINDOW-PARSER-000
/// tmux ウィンドウ出力のパース
library;

import '../tmux_delimiters.dart';
import '../tmux_models.dart';
import 'output_validator.dart';

/// tmux ウィンドウ出力のパース。
class TmuxWindowParser {
  // inventory: TMUX-PARSER-005
  /// ウィンドウ一覧をパース
  ///
  /// 対応フォーマット: `#{window_index}\t#{window_id}\t#{window_name}\t#{window_active}\t#{window_panes}\t#{window_flags}`
  static List<TmuxWindow> parse(
    String output, {
    TmuxDelimiters delimiters = TmuxOutputValidator.defaultDelimiters,
  }) {
    output = TmuxOutputValidator.normalizeDelimiters(output, delimiters);
    final windows = <TmuxWindow>[];

    for (final record in output.split(delimiters.record)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final window = parseLine(trimmed, delimiter: delimiters.field);
      if (window != null) {
        windows.add(window);
      }
    }

    return windows;
  }

  // inventory: TMUX-PARSER-006
  /// 単一のウィンドウ行をパース
  static TmuxWindow? parseLine(
    String line, {
    String delimiter = TmuxDelimiters.legacyField,
  }) {
    final parts = line.split(delimiter);
    if (parts.isEmpty) return null;

    final index = int.tryParse(parts[0]);
    if (index == null) return null;

    return TmuxWindow(
      index: index,
      id: parts.length > 1 ? parts[1] : null,
      name: parts.length > 2 ? parts[2] : 'window-$index',
      active: parts.length > 3 ? parts[3] == '1' : false,
      paneCount: parts.length > 4 ? int.tryParse(parts[4]) ?? 1 : 1,
      flags: parts.length > 5 ? parseFlags(parts[5]) : const {},
    );
  }

  // inventory: TMUX-PARSER-007
  /// 簡易フォーマットでウィンドウをパース
  ///
  /// フォーマット: `#{window_index}:#{window_name}:#{window_active}:#{window_panes}`
  static List<TmuxWindow> parseSimple(String output) {
    final windows = <TmuxWindow>[];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(':');
      if (parts.length >= 4) {
        windows.add(
          TmuxWindow(
            index: int.tryParse(parts[0]) ?? 0,
            name: parts[1],
            active: parts[2] == '1',
            paneCount: int.tryParse(parts[3]) ?? 1,
          ),
        );
      }
    }

    return windows;
  }

  // inventory: TMUX-PARSER-016
  /// ウィンドウフラグをパース（ツリー構築からも再利用される）
  static Set<TmuxWindowFlag> parseFlags(String flags) {
    final result = <TmuxWindowFlag>{};
    if (flags.contains('*')) result.add(TmuxWindowFlag.current);
    if (flags.contains('-')) result.add(TmuxWindowFlag.last);
    if (flags.contains('#')) result.add(TmuxWindowFlag.activity);
    if (flags.contains('!')) result.add(TmuxWindowFlag.bell);
    if (flags.contains('~')) result.add(TmuxWindowFlag.silence);
    if (flags.contains('M')) result.add(TmuxWindowFlag.marked);
    if (flags.contains('Z')) result.add(TmuxWindowFlag.zoomed);
    return result;
  }
}
