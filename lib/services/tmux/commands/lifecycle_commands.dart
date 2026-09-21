// inventory: TMUX-LIFECYCLE-CMD-000
/// tmux セッション復元トラップのシェルスクリプト生成
library;

import '../tmux_executable_resolver.dart';
import 'arg_quoting.dart';

/// tmux セッション復元トラップのシェルスクリプト生成。
class TmuxLifecycleCommands {
  // inventory: TMUX-CMD-025
  /// AutoResizeで縮めたウィンドウを、接続断時にサーバ側で自動復元するtrapを組み立てる。
  ///
  /// アプリがスワイプ終了・強制終了・クラッシュで復元コマンドを送れずに死んでも、
  /// SSHチャネルが閉じて入力シェルがHUP/EXIT/TERMする際にtmuxウィンドウが自動サイズへ
  /// 戻る（tmuxサーバはSSHシェルとは別プロセスなので生存しており復元コマンドは届く）。
  ///
  /// [tmuxBin] は検出済みのtmux絶対パス（シェル終了時はPATHが最小化される場合が
  /// あるため絶対パスを使う）。[targets] が空なら [clearWindowRestoreTrap] を返す。
  static String windowRestoreTrap(
    List<String> targets, {
    required String tmuxBin,
  }) {
    if (targets.isEmpty) return clearWindowRestoreTrap();
    // 全ターゲットを1回のtmux起動にまとめ、\;でコマンド連結する。teardown中に
    // 2つ目のtmuxプロセス起動がSIGKILLで打ち切られ、サイズ復元だけ実行されて
    // window-size manualの解除が漏れるのを防ぐ（単一プロセスなら両方まとめて完了）。
    final seq = targets
        .map((t) {
          final tt = ShellCommandComposer.quote(t);
          return 'resize-window -t $tt -A \\; set -uw -t $tt window-size';
        })
        .join(' \\; ');
    final quotedBin = TmuxExecutableResolver.shQuote(tmuxBin);
    final body = '$quotedBin $seq 2>/dev/null';
    // HUP必須: PTYチャネルclose時のSIGHUPはHUPを明示トラップしないとEXIT trapを
    // 実行せずシェルを終了させる。bodyは冪等なのでHUP後のEXITで二重実行しても無害。
    // ダブルクォートで囲み、quotedBin 内のシングルクォートを安全に埋め込む。
    return 'trap "$body" EXIT HUP TERM';
  }

  // inventory: TMUX-CMD-026
  /// [windowRestoreTrap] で設定したtrapを解除する。
  static String clearWindowRestoreTrap() => 'trap - EXIT HUP TERM';
}
