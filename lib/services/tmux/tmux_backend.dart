library;

/// tmux 入力シェル・backend transport の回復可能な失敗。
///
/// [TmuxInputTransport.sendNoWait] 等で発生し、呼出側が再起動や
/// exec fallback を判断できるようにする。
class TmuxTransportException implements Exception {
  final String message;
  final Object? cause;

  TmuxTransportException(this.message, [this.cause]);

  @override
  String toString() => 'TmuxTransportException: $message';
}

/// tmux 層が SSH 層から必要とする入力シェル能力。
///
/// 持続的シェル（persistent shell）の具象型を tmux 層に露出させないための
/// backend-neutral な最小限のインターフェース。
abstract interface class TmuxInputTransport {
  bool get isStarted;

  /// 出力を待たずに [data] を送信する。
  ///
  /// 送信不能な場合は [TmuxTransportException] を投げる。
  void sendNoWait(String data);
}

/// tmux 層が SSH 層に要求する backend-neutral transport 能力。
///
/// [SshClient] はこのインターフェースを実装し、tmux 層は
/// [SshClient] 具象型ではなく [TmuxBackend] だけに依存する。
abstract interface class TmuxBackend {
  bool get isConnected;

  Future<String> exec(String command, {Duration? timeout});
  Future<String> execPersistent(String command, {Duration? timeout});
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  });
  void write(String data);

  /// ユーザーが接続設定で指定した tmux パス。
  String? get userTmuxPath;

  /// 入力専用の持続的シェル。
  TmuxInputTransport? get inputTransport;

  /// 入力専用シェルを再起動する。
  Future<void> restartInputTransport();

  /// 入力シェルが再起動した際に呼ばれるコールバック。
  void Function()? get onInputTransportRebooted;
  set onInputTransportRebooted(void Function()? value);
}
