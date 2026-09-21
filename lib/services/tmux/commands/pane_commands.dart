// inventory: TMUX-PANE-CMD-000
/// tmux ペイン構造操作のコマンド文字列生成
library;

import 'arg_quoting.dart';

/// tmux ペイン構造操作（一覧以外）のコマンド文字列生成。
class TmuxPaneCommands {
  // inventory: TMUX-CMD-017
  /// ペインを選択
  static String select(String paneId) {
    return 'tmux select-pane -t ${ShellCommandComposer.quote(paneId)}';
  }

  // inventory: TMUX-CMD-018
  /// ペインを分割（水平）
  static String splitHorizontal({
    required String target,
    String? startDirectory,
    int? percentage,
  }) {
    final parts = [
      'tmux',
      'split-window',
      '-h',
      '-t',
      ShellCommandComposer.quote(target),
    ];
    if (percentage != null) parts.addAll(['-p', percentage.toString()]);
    if (startDirectory != null) {
      parts.addAll(['-c', ShellCommandComposer.quote(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-019
  /// ペインを分割（垂直）
  static String splitVertical({
    required String target,
    String? startDirectory,
    int? percentage,
  }) {
    final parts = [
      'tmux',
      'split-window',
      '-v',
      '-t',
      ShellCommandComposer.quote(target),
    ];
    if (percentage != null) parts.addAll(['-p', percentage.toString()]);
    if (startDirectory != null) {
      parts.addAll(['-c', ShellCommandComposer.quote(startDirectory)]);
    }
    return parts.join(' ');
  }

  // inventory: TMUX-CMD-020
  /// ペインを削除
  static String kill(String paneId) {
    return 'tmux kill-pane -t ${ShellCommandComposer.quote(paneId)}';
  }

  // inventory: TMUX-CMD-021
  /// ペインをズーム/アンズーム
  static String resize(String paneId, {bool zoom = true}) {
    return 'tmux resize-pane -t ${ShellCommandComposer.quote(paneId)} ${zoom ? '-Z' : '-z'}';
  }

  // inventory: TMUX-CMD-022
  /// ペインを指定サイズにリサイズする
  /// cols/rowsはオプション（片方のみ指定可、tmuxは未指定の方を変更しない）
  static String resizeToSize(String paneId, {int? cols, int? rows}) {
    final args = <String>['-t', ShellCommandComposer.quote(paneId)];
    if (cols != null) args.addAll(['-x', '$cols']);
    if (rows != null) args.addAll(['-y', '$rows']);
    return 'tmux resize-pane ${args.join(' ')}';
  }
}
