// inventory: TMUX-SESSION-PARSER-000
/// tmux セッション出力のパース
library;

import '../tmux_delimiters.dart';
import '../tmux_models.dart';
import 'output_validator.dart';

/// tmux セッション出力のパース。
class TmuxSessionParser {
  // inventory: TMUX-PARSER-002
  /// セッション一覧をパース
  ///
  /// 対応フォーマット: `#{session_name}\t#{session_created}\t#{session_attached}\t#{session_windows}\t#{session_id}`
  static List<TmuxSession> parse(
    String output, {
    TmuxDelimiters delimiters = TmuxOutputValidator.defaultDelimiters,
  }) {
    if (!TmuxOutputValidator.isServerRunning(output)) {
      return [];
    }
    output = TmuxOutputValidator.normalizeDelimiters(output, delimiters);

    final sessions = <TmuxSession>[];

    for (final record in output.split(delimiters.record)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final session = parseLine(trimmed, delimiter: delimiters.field);
      if (session != null) {
        sessions.add(session);
      }
    }

    return sessions;
  }

  // inventory: TMUX-PARSER-003
  /// 単一のセッション行をパース
  static TmuxSession? parseLine(
    String line, {
    String delimiter = TmuxDelimiters.legacyField,
  }) {
    final parts = line.split(delimiter);
    // 区切り文字が含まれない行はtmux出力ではない（シェルエラー等）
    if (parts.length < 2) return null;

    final name = parts[0];
    if (name.isEmpty) return null;

    return TmuxSession(
      name: name,
      id: parts.length > 4 ? parts[4] : null,
      created: parts.length > 1 ? _parseTimestamp(parts[1]) : null,
      attached: parts.length > 2 ? parts[2] == '1' : false,
      windowCount: parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0,
    );
  }

  // inventory: TMUX-PARSER-004
  /// 簡易フォーマットでセッションをパース
  ///
  /// フォーマット: `#{session_name}:#{session_windows}:#{session_attached}`
  static List<TmuxSession> parseSimple(String output) {
    if (!TmuxOutputValidator.isServerRunning(output)) return [];

    final sessions = <TmuxSession>[];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(':');
      if (parts.length >= 3) {
        sessions.add(
          TmuxSession(
            name: parts[0],
            windowCount: int.tryParse(parts[1]) ?? 0,
            attached: parts[2] == '1',
          ),
        );
      }
    }

    return sessions;
  }

  // inventory: TMUX-PARSER-014
  /// Unixタイムスタンプをパース
  static DateTime? _parseTimestamp(String value) {
    final seconds = int.tryParse(value);
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}
