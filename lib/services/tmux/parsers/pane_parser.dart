// inventory: TMUX-PANE-PARSER-000
/// tmux ペイン出力のパース
library;

import '../tmux_delimiters.dart';
import '../tmux_models.dart';
import 'output_validator.dart';

/// tmux ペイン出力のパース。
class TmuxPaneParser {
  // inventory: TMUX-PARSER-008
  /// ペイン一覧をパース
  ///
  /// 対応フォーマット: `#{pane_index}\t#{pane_id}\t#{pane_active}\t#{pane_current_command}\t#{pane_title}\t#{pane_width}\t#{pane_height}\t#{cursor_x}\t#{cursor_y}`
  static List<TmuxPane> parse(
    String output, {
    TmuxDelimiters delimiters = TmuxOutputValidator.defaultDelimiters,
  }) {
    output = TmuxOutputValidator.normalizeDelimiters(output, delimiters);
    final panes = <TmuxPane>[];

    for (final record in output.split(delimiters.record)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final pane = parseLine(trimmed, delimiter: delimiters.field);
      if (pane != null) {
        panes.add(pane);
      }
    }

    return panes;
  }

  // inventory: TMUX-PARSER-009
  /// 単一のペイン行をパース
  static TmuxPane? parseLine(
    String line, {
    String delimiter = TmuxDelimiters.legacyField,
  }) {
    final parts = line.split(delimiter);
    if (parts.length < 2) return null;

    final index = int.tryParse(parts[0]);
    if (index == null) return null;

    final id = parts[1];
    if (id.isEmpty) return null;

    return TmuxPane(
      index: index,
      id: id,
      active: parts.length > 2 ? parts[2] == '1' : false,
      currentCommand: parts.length > 3 ? parts[3] : null,
      title: parts.length > 4 ? parts[4] : null,
      width: parts.length > 5 ? int.tryParse(parts[5]) ?? 80 : 80,
      height: parts.length > 6 ? int.tryParse(parts[6]) ?? 24 : 24,
      cursorX: parts.length > 7 ? int.tryParse(parts[7]) ?? 0 : 0,
      cursorY: parts.length > 8 ? int.tryParse(parts[8]) ?? 0 : 0,
    );
  }

  // inventory: TMUX-PARSER-010
  /// 簡易フォーマットでペインをパース
  ///
  /// フォーマット: `#{pane_index}:#{pane_id}:#{pane_active}:#{pane_width}x#{pane_height}`
  static List<TmuxPane> parseSimple(String output) {
    final panes = <TmuxPane>[];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(':');
      if (parts.length >= 4) {
        final size = _parseSize(parts[3]);
        panes.add(
          TmuxPane(
            index: int.tryParse(parts[0]) ?? 0,
            id: parts[1],
            active: parts[2] == '1',
            width: size.width,
            height: size.height,
          ),
        );
      }
    }

    return panes;
  }

  // inventory: TMUX-PARSER-015
  /// サイズ文字列をパース（例: "80x24"）
  static ({int width, int height}) _parseSize(String value) {
    final parts = value.split('x');
    return (
      width: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 80 : 80,
      height: parts.length > 1 ? int.tryParse(parts[1]) ?? 24 : 24,
    );
  }
}
