// inventory: HERDR-CARET-ARGS-000
/// リモートシェルへ安全な値を渡すための静的ユーティリティ。
///
/// client socket 導出（`derive_client_socket_from_api_socket` と同じ規則）・
/// pane ID 検証・POSIX single-quote エスケープを担う。値を検証・引用して
/// からでないと shell 引数として使用しない（セキュリティ規則 L1）。
library;

import 'package:path/path.dart' as p;

/// シェル引数の構築・検証（状態なし・静的）。
class HerdrCaretShellArgs {
  /// API socket（`herdr status --json` の `server.socket`）から
  /// client socket を導出する。
  ///
  /// `derive_client_socket_from_api_socket` と同じ規則:
  /// 同ディレクトリの `file_stem + "-client.sock"`。
  /// dirname が `.`（bare ファイル名）の場合は `./` を付けずに返す。
  static String deriveClientSocket(String apiSocket) {
    final dir = p.posix.dirname(apiSocket);
    final stem = p.posix.basenameWithoutExtension(apiSocket);
    final name = '$stem-client.sock';
    return dir == '.' ? name : p.posix.join(dir, name);
  }

  /// pane ID の書式検証（長さ 1..64・印字可能 ASCII・制御文字なし）。
  ///
  /// 書式をクライアント側で捏造せず、この検証を通過した値だけを
  /// shell 引数として使う。
  static bool isValidPaneId(String paneId) {
    if (paneId.isEmpty || paneId.length > 64) return false;
    for (final unit in paneId.codeUnits) {
      if (unit < 0x20 || unit > 0x7E) return false;
    }
    return true;
  }

  /// POSIX single-quote エスケープ（`'...'` 内の `'` は `'\''`）。
  static String shellQuote(String arg) => "'${arg.replaceAll("'", r"'\''")}'";
}
