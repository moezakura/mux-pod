import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
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
    implements TmuxCommandExecutor, TmuxPathDetector {
  @override
  SshConnectionState state = SshConnectionState.connected;

  @override
  bool get isConnected => state == SshConnectionState.connected;

  @override
  String? lastError;

  @override
  String? tmuxPath;

  @override
  String? userTmuxPath;

  final _connectionStateController =
      StreamController<SshConnectionState>.broadcast();

  @override
  Stream<SshConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// [exec] / [execPersistent] / [execWithExitCode] で返す fixture。
  /// `command` の接頭辞で一意に識別。
  Map<String, String> execOutputs = {};

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

  FakeSshClient({this.tmuxPath = 'tmux'});

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
    if (tmuxPath == null) return command;
    final escaped = RegExp.escape(tmuxPath!);
    return command.replaceAll(
      RegExp("'$escaped'"),
      tmuxPath!,
    );
  }

  bool _matches(String command, String key) =>
      command.startsWith(key) ||
      command.contains(key) ||
      _normalize(command).startsWith(key) ||
      _normalize(command).contains(key);

  String _lookupOutput(String command) {
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

  @override
  Future<String> execPersistent(
    String command, {
    Duration? timeout,
  }) async {
    execPersistentCommands.add(command);
    return exec(command, timeout: timeout);
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
