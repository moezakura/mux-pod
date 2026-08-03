// inventory: TMUX-SSH-EXEC-000
/// SSH 接続をラップした `TmuxCommandExecutor` 実装。
///
/// tmux 実行ファイルの検出・パス解決・入力専用シェル・restore trap など、
/// Tmux 固有の責務を SSH 層から分離して担う。
///
/// 具象の [SshClient] ではなく [TmuxBackend] 抽象に依存し、
/// [TmuxInputTransport] だけを使用して入力シェルとの通信を行う。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tmux_backend.dart';
import 'tmux_command_executor.dart';
import 'tmux_executable_resolver.dart';
import 'tmux_shell_lifecycle.dart';

// inventory: TMUX-SSH-EXEC-001
class SshTmuxCommandExecutor implements TmuxCommandExecutor {
  final TmuxBackend _backend;
  final TmuxExecutableResolver _resolver;
  final String? _userTmuxPath;
  late final TmuxShellLifecycle _lifecycle;

  String? _lastRestoreTrapCommand;
  bool _detected = false;
  Future<void>? _detectFuture;

  // inventory: TMUX-SSH-EXEC-002
  SshTmuxCommandExecutor(
    this._backend, {
    String? userTmuxPath,
  })  : _userTmuxPath = userTmuxPath ?? _backend.userTmuxPath,
        _resolver = TmuxExecutableResolver() {
    _lifecycle = TmuxShellLifecycle(resolver: _resolver);
    _backend.onInputTransportRebooted = _reapplyLastRestoreTrap;
  }

  Future<void> _ensureDetected() async {
    if (_detected) return;
    if (_detectFuture != null) return _detectFuture!;
    _detectFuture = _resolver.detect(
      _TmuxBackendPathDetector(_backend),
      userTmuxPath: _userTmuxPath,
    );
    try {
      await _detectFuture!;
      _detected = true;
    } catch (_) {
      _detected = false;
      _detectFuture = null;
      rethrow;
    }
  }

  @override
  // inventory: TMUX-SSH-EXEC-003
  bool get isConnected => _backend.isConnected;

  @override
  // inventory: TMUX-SSH-EXEC-005
  String? get tmuxPath => _resolver.tmuxPath;

  /// 内部で使用している [TmuxShellLifecycle]（テスト用）。
  TmuxShellLifecycle get lifecycle => _lifecycle;

  @override
  // inventory: TMUX-SSH-EXEC-006
  Future<String> exec(String command, {Duration? timeout}) async {
    await _ensureDetected();
    final resolved = _resolver.resolve(command);
    return _backend.exec(resolved, timeout: timeout);
  }

  @override
  // inventory: TMUX-SSH-EXEC-007
  Future<String> execPersistent(
    String command, {
    Duration? timeout,
  }) async {
    await _ensureDetected();
    final resolved = _resolver.resolve(command);
    return _backend.execPersistent(resolved, timeout: timeout);
  }

  @override
  // inventory: TMUX-SSH-EXEC-008
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    await _ensureDetected();
    final resolved = _resolver.resolve(command);
    return _backend.execWithExitCode(resolved, timeout: timeout);
  }

  @override
  // inventory: TMUX-SSH-EXEC-009
  void write(String data) {
    _backend.write(data);
  }

  @override
  // inventory: TMUX-SSH-EXEC-010
  Future<void> sendKeysCommand(String command) async {
    await _ensureDetected();
    final resolved = _resolver.resolve(command);
    final input = _backend.inputTransport;
    if (input != null && input.isStarted) {
      try {
        input.sendNoWait(resolved);
        return;
      } on TmuxTransportException {
        unawaited(_backend.restartInputTransport());
      }
    }
    await exec(resolved);
  }

  @override
  // inventory: TMUX-SSH-EXEC-011
  Future<void> setWindowRestoreTrap(List<String> windowTargets) async {
    await _ensureDetected();
    final cmd = windowTargets.isEmpty
        ? _lifecycle.buildClearRestoreTrapCommand()
        : _lifecycle.buildRestoreTrapCommand(
            windowTargets,
            tmuxBin: _resolver.tmuxBin,
          );
    _lifecycle.setRestoreTrapCommand(windowTargets.isEmpty ? null : cmd);
    _lastRestoreTrapCommand = _lifecycle.currentRestoreTrapCommand;
    final input = _backend.inputTransport;
    if (input == null || !input.isStarted) return;
    try {
      input.sendNoWait(cmd);
    } on TmuxTransportException {
      unawaited(_backend.restartInputTransport());
    }
  }

  @override
  // inventory: TMUX-SSH-EXEC-012
  Future<void> restoreWindowsNoWait(List<String> targets) async {
    if (targets.isEmpty) return;
    await _ensureDetected();
    final input = _backend.inputTransport;
    for (final t in targets) {
      final cmd = _resolver.resolve(
        _lifecycle.buildResizeAutoCommand(t, tmuxBin: _resolver.tmuxBin),
      );
      if (input != null && input.isStarted) {
        try {
          input.sendNoWait(cmd);
          continue;
        } on TmuxTransportException {
          unawaited(_backend.restartInputTransport());
        }
      }
      try {
        await exec(cmd);
      } on TmuxTransportException {
        unawaited(_backend.restartInputTransport());
      }
    }
  }

  // inventory: TMUX-SSH-EXEC-013
  /// 入力シェルが再起動した際、最後に設定した restore trap を再適用する。
  void _reapplyLastRestoreTrap() {
    final cmd = _lastRestoreTrapCommand;
    final input = _backend.inputTransport;
    if (cmd == null || input == null || !input.isStarted) return;
    try {
      input.sendNoWait(cmd);
    } on TmuxTransportException catch (e) {
      // 再起動直後の送信失敗は無視
      debugPrint('[_reapplyLastRestoreTrap] send failed: $e');
    }
  }
}

// inventory: TMUX-SSH-EXEC-016
/// [TmuxBackend] を [TmuxPathDetector] として利用する薄いラッパー。
///
/// [SshTmuxCommandExecutor] 自身を渡すと `_ensureDetected` が再帰するため、
/// 検出中はこのラッパー経由で raw transport のみを使う。
class _TmuxBackendPathDetector implements TmuxPathDetector {
  final TmuxBackend _backend;

  _TmuxBackendPathDetector(this._backend);

  @override
  bool get isConnected => _backend.isConnected;

  @override
  Future<String> exec(String command, {Duration? timeout}) =>
      _backend.exec(command, timeout: timeout);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) =>
      _backend.execWithExitCode(command, timeout: timeout);
}

// inventory: TMUX-SSH-EXEC-014
/// [TmuxBackend] から [TmuxCommandExecutor] を取得する拡張。
///
/// 同一の backend インスタンスに対しては [Expando] で
/// [SshTmuxCommandExecutor] を共有可能化し、Tmux パス検出や
/// restore trap 状態を再利用する。
/// [TmuxBackend] 自体が [TmuxCommandExecutor] を実装している場合
/// （テスト用の [FakeSshClient] など）はラップせずそのまま返す。
final _sshExecutors = Expando<SshTmuxCommandExecutor>();

// inventory: TMUX-SSH-EXEC-015
extension TmuxBackendExecutor on TmuxBackend {
  TmuxCommandExecutor get tmuxExecutor {
    if (this is TmuxCommandExecutor) return this as TmuxCommandExecutor;
    return _sshExecutors[this] ??= SshTmuxCommandExecutor(
      this,
      userTmuxPath: userTmuxPath,
    );
  }
}


