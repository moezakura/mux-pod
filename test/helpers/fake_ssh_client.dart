import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/command/command_result.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/services/tmux/tmux_backend.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_builder.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_executable_resolver.dart';
import 'fake_sftp_client.dart';

/// [SshClient]（MuxPod ラッパー）の手書き fake。
///
/// テスト用に実行ログと fixture 応答を提供する。
class FakeSshClient extends SshClient
    implements TmuxCommandExecutor, TmuxPathDetector, BackendAdapter {
  @override
  SshConnectionState state = SshConnectionState.connected;

  @override
  bool get isConnected => state == SshConnectionState.connected;

  @override
  String? lastError;

  /// 検出・解決済み tmux パス（[TmuxCommandExecutor.tmuxPath] 用）。
  String? executablePath;

  /// ユーザーが指定した実行ファイルパス（[BackendAdapter.userExecutablePath] 用）。
  @override
  String? userExecutablePath;

  /// 互換用 [TmuxCommandExecutor.tmuxPath] ゲッター。
  @override
  String? get tmuxPath => executablePath;
  set tmuxPath(String? value) => executablePath = value;

  final _connectionStateController =
      StreamController<SshConnectionState>.broadcast();

  @override
  Stream<SshConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// [exec] / [execPersistent] / [execWithExitCode] で返す fixture。
  /// `command` の接頭辞で一意に識別。
  Map<String, String> execOutputs = {};

  /// Prefix/substring keyed FIFO responses for polling and refresh scenarios.
  final Map<String, List<String>> execOutputQueues = {};

  /// [execWithExitCode] 用の終了コード fixture。
  Map<String, int> execExitCodes = {};

  /// 特定コマンドで [exec] / [execWithExitCode] が throw する例外 fixture。
  Map<String, Exception> execExceptions = {};

  /// 送られたすべてのコマンドを記録。
  final List<String> execCommands = [];
  final List<String> execPersistentCommands = [];
  final List<String> sendKeysCommands = [];
  final List<String> restoreWindowCommands = [];
  final List<List<String>> setWindowRestoreTrapCalls = [];
  final List<String> writtenData = [];
  final List<(int, int)> resizes = [];

  /// SFTP fixture。
  late FakeSftpClient sftpClient = FakeSftpClient();

  /// テスト用の [TmuxInputTransport]。
  TmuxInputTransport? fakeInputTransport;

  /// [restartInputTransport] の呼び出し回数。
  int restartInputTransportCount = 0;

  FakeSshClient({this.executablePath = 'tmux', this.userExecutablePath});

  @override
  TmuxInputTransport? get inputTransport => fakeInputTransport;

  @override
  Future<void> restartInputTransport() async {
    restartInputTransportCount++;
  }

  void setConnected(SshConnectionState value) {
    state = value;
    _connectionStateController.add(value);
  }

  @override
  Future<SftpClient> openSftp() async => sftpClient;

  String _normalize(String command) {
    final path = executablePath;
    if (path == null) return command;
    final escaped = RegExp.escape(path);
    return command.replaceAll(RegExp("'$escaped'"), path);
  }

  bool _matches(String command, String key) =>
      command.startsWith(key) ||
      command.contains(key) ||
      _normalize(command).startsWith(key) ||
      _normalize(command).contains(key);

  String _lookupOutput(String command) {
    for (final entry in execOutputQueues.entries) {
      if (_matches(command, entry.key) && entry.value.isNotEmpty) {
        return entry.value.removeAt(0);
      }
    }
    return execOutputs.entries
        .firstWhere(
          (e) => _matches(command, e.key),
          orElse: () => MapEntry('', ''),
        )
        .value;
  }

  int _lookupExitCode(String command) {
    if (execExitCodes.containsKey(command)) return execExitCodes[command]!;
    final normalized = _normalize(command);
    if (execExitCodes.containsKey(normalized)) {
      return execExitCodes[normalized]!;
    }
    for (final entry in execExitCodes.entries) {
      if (_matches(command, entry.key)) return entry.value;
    }
    return 0;
  }

  @override
  Future<String> exec(String command, {Duration? timeout}) async {
    execCommands.add(command);
    for (final e in execExceptions.entries) {
      if (_matches(command, e.key)) {
        throw e.value;
      }
    }
    return _lookupOutput(command);
  }

  Future<String> execPersistent(String command, {Duration? timeout}) async {
    execPersistentCommands.add(command);
    return exec(command, timeout: timeout);
  }

  @override
  Future<CommandResult> execute(CommandRequest request) async {
    // persistent 要求のみ execPersistentCommands に記録する（テスト観測性）。
    // それ以外（ephemeral）は execCommands 側で記録される。
    final usePersistent =
        request.transport == CommandTransportPreference.persistentPreferred ||
        request.transport == CommandTransportPreference.persistentOnly;
    final result = usePersistent
        ? await execPersistentWithExitCode(request.command)
        : await execWithExitCode(request.command);
    return CommandResult(
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      outputSeparation: CommandOutputSeparation.separated,
      actualTransport: usePersistent
          ? CommandTransport.persistent
          : CommandTransport.ephemeral,
    );
  }

  Future<({String stdout, String stderr, int? exitCode})>
  execPersistentWithExitCode(String command, {Duration? timeout}) async {
    execPersistentCommands.add(command);
    return execWithExitCode(command, timeout: timeout);
  }

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    for (final e in execExceptions.entries) {
      if (_matches(command, e.key)) {
        throw e.value;
      }
    }
    final output = _lookupOutput(command);
    final exitCode = _lookupExitCode(command);
    return (stdout: output, stderr: '', exitCode: exitCode);
  }

  @override
  Future<void> sendKeysCommand(String command) async {
    sendKeysCommands.add(command);
  }

  @override
  Future<void> setWindowRestoreTrap(List<String> windowTargets) async {
    setWindowRestoreTrapCalls.add(List.of(windowTargets));
  }

  @override
  Future<void> restoreWindowsNoWait(List<String> targets) async {
    for (final t in targets) {
      restoreWindowCommands.add(TmuxCommands.resizeWindowAuto(t));
    }
  }

  @override
  void write(String data) {
    writtenData.add(data);
  }

  @override
  void writeBytes(Uint8List data) {
    writtenData.add(String.fromCharCodes(data));
  }

  @override
  void resize(int cols, int rows) {
    resizes.add((cols, rows));
  }

  @override
  Future<void> startShell([ShellOptions options = const ShellOptions()]) async {
    // no-op
  }

  @override
  Future<void> disconnect() async {
    setConnected(SshConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await _connectionStateController.close();
  }

  @override
  void setEventHandlers(SshEvents events) {}

  @override
  void updateEventHandlers({
    void Function(Uint8List data)? onData,
    void Function()? onClose,
    void Function(Object error)? onError,
  }) {}

  @override
  Future<void> restartPersistentShell() async {}
}
