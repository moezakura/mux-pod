/// backend 入力トランスポートの回復可能な失敗。
///
/// [BackendInputTransport.sendNoWait] 等で発生し、呼出側が再起動や
/// exec fallback を判断できるようにする。
class BackendTransportException implements Exception {
  /// エラーメッセージ
  final String message;

  /// 元の例外（任意）
  final Object? cause;

  BackendTransportException(this.message, [this.cause]);

  @override
  String toString() => 'BackendTransportException: $message';
}

/// backend 層が SSH 層から必要とする入力シェル能力。
///
/// 持続的シェル（persistent shell）の具象型を backend 層に露出させないための
/// 汎用な最小限のインターフェース。
abstract interface class BackendInputTransport {
  /// 入力シェルが開始されているかどうか。
  bool get isStarted;

  /// 出力を待たずに [data] を送信する。
  ///
  /// 送信不能な場合は [BackendTransportException] を投げる。
  void sendNoWait(String data);
}

/// backend 非依存の transport 能力。
///
/// [SshClient] は [BackendAdapter]（互換名 [TmuxBackend]）としてこのインターフェースを
/// 実装する。backend 層は具象型ではなくこの抽象に依存する。
abstract interface class BackendAdapter {
  /// 接続中かどうか。
  bool get isConnected;

  /// コマンドを実行して結果を取得する。
  Future<String> exec(String command, {Duration? timeout});

  /// 持続的シェル経由でコマンドを実行する。
  Future<String> execPersistent(String command, {Duration? timeout});

  /// コマンドを実行して標準出力・標準エラー・終了コードを取得する。
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  });

  /// データを書き込む。
  void write(String data);

  /// ユーザーが接続設定で指定した実行ファイルパス。
  String? get userExecutablePath;

  /// 入力専用の持続的シェル。
  BackendInputTransport? get inputTransport;

  /// 入力専用シェルを再起動する。
  Future<void> restartInputTransport();

  /// 入力シェルが再起動した際に呼ばれるコールバック。
  void Function()? get onInputTransportRebooted;
  set onInputTransportRebooted(void Function()? value);
}
