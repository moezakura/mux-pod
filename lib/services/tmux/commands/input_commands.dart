// inventory: TMUX-INPUT-CMD-000
/// tmux ペインへの入力・ペースト・コピーモード操作のコマンド文字列生成
library;

import 'dart:convert';
import 'dart:math';

import 'arg_quoting.dart';

/// tmux ペインへの入力・ペースト・コピーモード操作のコマンド文字列生成。
///
/// base64 ペースト / ランダムID 生成はこのクラスに内包する。
class TmuxInputCommands {
  // inventory: TMUX-CMD-027
  /// キーを送信
  static String sendKeys(String paneId, String keys, {bool literal = false}) {
    final escapedKeys = ShellCommandComposer.quote(keys);
    // `--` で tmux 側のオプション解析を打ち切る。これがないと、ダッシュで
    // 始まる入力（例: `-X`）が send-keys のオプションとして解釈され、
    // 文字入力ではなくコピーモード操作等に化ける。
    if (literal) {
      return 'tmux send-keys -t ${ShellCommandComposer.quote(paneId)} -l -- $escapedKeys';
    }
    return 'tmux send-keys -t ${ShellCommandComposer.quote(paneId)} -- $escapedKeys';
  }

  // inventory: TMUX-CMD-028
  /// Enterキーを送信
  static String sendEnter(String paneId) {
    return 'tmux send-keys -t ${ShellCommandComposer.quote(paneId)} Enter';
  }

  // inventory: TMUX-CMD-029
  /// Build a single shell command that loads [text] into a named tmux
  /// buffer and pastes it into the given [target] pane using bracketed
  /// paste mode (`paste-buffer -p`).
  ///
  /// Intended for multi-line text only; single-key / control-key paths
  /// use [sendKeys] directly.
  ///
  /// The payload is base64-encoded in transit so any shell-special
  /// characters in [text] do not need extra escaping. The receiving
  /// remote is expected to have a POSIX `base64` binary on PATH.
  ///
  /// The buffer is named with a microsecond timestamp plus a random hex
  /// suffix to avoid collisions when multiple paste operations run
  /// concurrently. `-d` deletes the buffer immediately after pasting.
  ///
  /// Practical upper bound: tested up to ~100 KB; very large pastes may
  /// exceed ARG_MAX (~256 KB on macOS, ~2 MB on Linux). True stdin-piping
  /// via dartssh2 would remove this limit but is deferred.
  ///
  /// Note: requires tmux >= 2.6 for `-p` (bracketed paste). Use
  /// [pasteNoBracketed] as a fallback for older tmux.
  static String paste(String target, String text) {
    final encoded = base64.encode(utf8.encode(text));
    final rand = Random().nextInt(0xffffff).toRadixString(16).padLeft(6, '0');
    // bufName is safe: numeric + lowercase hex only — no escaping needed.
    final bufName = 'muxpod-${DateTime.now().microsecondsSinceEpoch}-$rand';
    return "printf '%s' '$encoded' | base64 -d "
        "| tmux load-buffer -b '$bufName' - "
        "&& tmux paste-buffer -d -p -b '$bufName' -t ${ShellCommandComposer.quote(target)}";
  }

  // inventory: TMUX-CMD-030
  /// Fallback variant of [paste] for tmux < 2.6, which does
  /// not support the `-p` (bracketed paste) flag on `paste-buffer`.
  ///
  /// Prefer [paste] when the remote tmux version is >= 2.6.
  static String pasteNoBracketed(String target, String text) {
    final encoded = base64.encode(utf8.encode(text));
    final rand = Random().nextInt(0xffffff).toRadixString(16).padLeft(6, '0');
    // bufName is safe: numeric + lowercase hex only — no escaping needed.
    final bufName = 'muxpod-${DateTime.now().microsecondsSinceEpoch}-$rand';
    return "printf '%s' '$encoded' | base64 -d "
        "| tmux load-buffer -b '$bufName' - "
        "&& tmux paste-buffer -d -b '$bufName' -t ${ShellCommandComposer.quote(target)}";
  }

  // inventory: TMUX-CMD-031
  /// Ctrl+Cを送信
  static String sendInterrupt(String paneId) {
    return 'tmux send-keys -t ${ShellCommandComposer.quote(paneId)} C-c';
  }

  // inventory: TMUX-CMD-032
  /// エスケープキーを送信
  static String sendEscape(String paneId) {
    return 'tmux send-keys -t ${ShellCommandComposer.quote(paneId)} Escape';
  }

  // inventory: TMUX-CMD-035
  /// copy-modeに入る
  static String enterCopyMode(String target) {
    return 'tmux copy-mode -t ${ShellCommandComposer.quote(target)}';
  }

  // inventory: TMUX-CMD-036
  /// copy-modeを終了（copy-mode中のみ有効、非copy-mode時は無害）
  static String cancelCopyMode(String target) {
    return 'tmux send-keys -t ${ShellCommandComposer.quote(target)} -X cancel';
  }
}
