library;

import '../backend/backend_adapter.dart';

export '../backend/backend_adapter.dart';

/// tmux 入力シェル・backend transport の回復可能な失敗。
///
/// [TmuxInputTransport.sendNoWait] 等で発生し、呼出側が再起動や
/// exec fallback を判断できるようにする。
class TmuxTransportException extends BackendTransportException {
  TmuxTransportException(super.message, [super.cause]);

  @override
  String toString() => 'TmuxTransportException: $message';
}

/// tmux 層が SSH 層から必要とする入力シェル能力。
///
/// 持続的シェル（persistent shell）の具象型を tmux 層に露出させないための
/// backend-neutral な最小限のインターフェース。
abstract interface class TmuxInputTransport implements BackendInputTransport {
  /// 入力シェルが開始されているかどうか。
  @override
  bool get isStarted;

  /// 出力を待たずに [data] を送信する。
  ///
  /// 送信不能な場合は [TmuxTransportException] を投げる。
  @override
  void sendNoWait(String data);
}

/// tmux 層が SSH 層に要求する backend-neutral transport 能力。
///
/// [SshClient] は [BackendAdapter] を実装し、tmux 層は
/// [SshClient] 具象型ではなく [TmuxBackend] / [BackendAdapter] 抽象に依存する。
///
/// [TmuxBackend] は [BackendAdapter] の互換名（alias）である。
typedef TmuxBackend = BackendAdapter;
