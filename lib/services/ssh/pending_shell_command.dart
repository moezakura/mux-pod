import 'dart:async';

import 'shell_marker_scanner.dart';

/// 実行中のコマンドの状態（per-command・immutable な設定 + 可変の進捗）。
///
/// 従来 shell 全体で持っていた `_pendingCommand` / `_captureExitCode` /
/// `_lastExitCode` / `_scanner` を実行単位に集約する（Codex 根本設計レビュー・
/// バグ2 根本対応）。[scanner] はコマンドごとに新しく生成し、timeout 後に
/// 旧コマンドの遅延フレームが新コマンドに混入するのを防ぐ。
final class PendingShellCommand {
  PendingShellCommand({
    required this.captureExitCode,
    required ShellMarkerScanner Function() scannerFactory,
  }) : scanner = scannerFactory();

  /// 終了コードを捕捉するか（RC エコーを付与したか）。
  final bool captureExitCode;

  /// このコマンドの結果を待つ completer。
  final Completer<String> completer = Completer<String>();

  /// このコマンド用のマーカースキャナ。
  final ShellMarkerScanner scanner;

  /// 捕捉した終了コード（未捕捉なら null）。
  int? exitCode;

  bool get isCompleted => completer.isCompleted;
}
