// inventory: TMUX-ARG-QUOTING-000
/// シェルコマンド文字列の合成（引数クオート・連結・パイプ）
library;

/// シェルコマンド文字列の合成ユーティリティ。
///
/// tmux コマンドの引数クオート、コマンド連結、パイプ連結を担う。
class ShellCommandComposer {
  // inventory: TMUX-ESC-001
  /// 引数をエスケープ
  static String quote(String arg) {
    // 制御文字（0x00-0x1F / 0x7F）を含む場合は bash の ANSI-C quoting
    // （$'...'）で送る。ダブルクォート等の通常の引用符では、コマンドライン
    // 内の制御文字（Ctrl+A = 行頭移動、Ctrl+O = 履歴操作等）を対話シェルの
    // readline が解釈して失うため（herdr の _shellQuote と同様）。
    if (arg.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      final buffer = StringBuffer("\$");
      buffer.write("'");
      for (final rune in arg.runes) {
        if (rune < 0x20 || rune == 0x7f) {
          buffer.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
        } else if (rune == 0x5c) {
          // backslash
          buffer.write(r'\\');
        } else if (rune == 0x27) {
          // single quote
          buffer.write(r"\'");
        } else {
          buffer.writeCharCode(rune);
        }
      }
      buffer.write("'");
      return buffer.toString();
    }

    // シェルの特殊文字をエスケープ
    // 特殊文字: スペース、クォート、バックスラッシュ、変数展開、バッククォート、
    // グロブ（*?）、チルダ（~）、コメント（#）、その他
    if (arg.contains(
      RegExp(
        r'[\s"'
        "'"
        r'\\$`!{}\[\]<>|&;()*?~#]',
      ),
    )) {
      // ダブルクォートでラップし、内部の特殊文字をエスケープ
      final escaped = arg
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"')
          .replaceAll(r'$', r'\$')
          .replaceAll('`', r'\`');
      return '"$escaped"';
    }
    return arg;
  }

  // inventory: TMUX-UTIL-001
  /// 複数のコマンドを連結
  static String join(List<String> commands) {
    return commands.join(' && ');
  }

  // inventory: TMUX-UTIL-002
  /// コマンドをパイプで連結
  static String pipeline(List<String> commands) {
    return commands.join(' | ');
  }
}
