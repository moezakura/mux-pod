library;

import 'package:flutter/foundation.dart';

/// tmux 実行ファイルパスの検出に必要な最小限の実行能力。
///
/// [SshClient] などの transport 実装を tmux 層に直接露出させず、
/// このインターフェースのみを検出に使用する。
abstract interface class TmuxPathDetector {
  bool get isConnected;
  Future<String> exec(String command, {Duration? timeout});
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  });
}

/// tmux 実行ファイルパスの検出とコマンド内の `tmux` を解決する。
class TmuxExecutableResolver {
  String? _tmuxPath;
  String? _customPath;

  /// 検出済みの tmux 絶対パス（未検出なら null）。
  String? get tmuxPath => _tmuxPath;

  /// ユーザーが明示した tmux パス（未指定なら null）。
  String? get customPath => _customPath;

  /// 検出済みの tmux パス、未検出時は `tmux` コマンド名。
  ///
  /// 返り値はクォートされていない生のコマンド/パス。シェル文字列に組み込む際は
  /// [shQuote] を使用する。
  String get tmuxBin {
    final path = _tmuxPath ?? _customPath;
    if (path != null) return path;
    return 'tmux';
  }

  // inventory: SSH-LIFE-005
  /// リモートで tmux 実行ファイルを検出する。
  ///
  /// [executablePath] が指定されていればその存在確認のみを行い、
  /// 成功時はそれを使用する。失敗時は `null` とする。
  /// [executablePath] が未指定の場合は、ログインシェル経由の
  /// `command -v tmux` と既知パスのフォールバックを試行する。
  ///
  Future<void> detect(
    TmuxPathDetector detector, {
    String? executablePath,
  }) async {
    if (!detector.isConnected) return;

    final path = (executablePath?.isNotEmpty == true) ? executablePath : null;

    if (path != null) {
      _customPath = path;
      final result = await detector.execWithExitCode(
        'test -x ${shQuote(path)}',
      );
      if (result.exitCode == 0) {
        _tmuxPath = path;
        debugPrint(
          'TmuxExecutableResolver: user-specified path verified: $_tmuxPath',
        );
        return;
      }
      debugPrint(
        'TmuxExecutableResolver: user-specified path not found: $path',
      );
      _tmuxPath = null;
      return;
    }

    // Step 1: ログインシェル経由で検出
    try {
      final output = await detector.exec(r"$SHELL -lc 'command -v tmux'");
      final path = output.trim();
      if (path.isNotEmpty && path.startsWith('/')) {
        _tmuxPath = path;
        debugPrint('TmuxExecutableResolver: found via login shell: $path');
        return;
      }
    } catch (e) {
      debugPrint('TmuxExecutableResolver: login shell detection failed: $e');
    }

    // Step 2: 既知パスのフォールバック
    const candidates = [
      '/opt/homebrew/bin/tmux',
      '/usr/local/bin/tmux',
      '/usr/bin/tmux',
    ];

    for (final candidate in candidates) {
      try {
        final result = await detector.execWithExitCode('test -x $candidate');
        if (result.exitCode == 0) {
          _tmuxPath = candidate;
          debugPrint('TmuxExecutableResolver: found via fallback: $candidate');
          return;
        }
      } catch (e) {
        debugPrint('TmuxExecutableResolver: error checking $candidate: $e');
      }
    }

    debugPrint('TmuxExecutableResolver: tmux not found');
    _tmuxPath = null;
  }

  // inventory: SSH-LIFE-006
  /// [command] 内の `tmux` コマンドを解決済み絶対パスに置換する。
  ///
  /// ユーザーが明示パスを指定していればそれを優先し、検出失敗時も
  /// そのパスをそのまま使用して bare `tmux` への勝手な fallback を防ぐ。
  /// 未指定時のみ bare `tmux` または自動検出したパスを使用する。
  /// 挿入するパスは [shQuote] 済みのため、ユーザ入力によるシェルインジェクション
  /// を防ぐ。
  String resolve(String command) {
    final bin = tmuxBin;
    if (bin == 'tmux') return command;
    final quoted = shQuote(bin);
    return command.replaceAllMapped(
      RegExp(r'(^|;\s*)tmux\b'),
      (m) => '${m[1]}$quoted',
    );
  }

  // inventory: SSH-LIFE-007
  /// シェル引数を単一引用符で安全に囲む。
  static String shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
}
