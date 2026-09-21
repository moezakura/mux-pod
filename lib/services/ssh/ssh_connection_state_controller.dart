import 'dart:async';

import 'ssh_connection_state.dart';

/// 接続状態の単一所有者。
///
/// state / lastError / connectionStateStream を保持し、遷移（connecting /
/// connected / error / disconnected）とストリーム発行のみを行う。
///
/// 発行セマンティクスは HEAD の `SshClient` と同一:
/// - [setState]: ストリーム発行なしの代入（connect() の connecting/connected、
///   シェル done の disconnected など HEAD が直接 `_state = ...` していた箇所）。
/// - [transition]: 変化時のみストリームへ発行（HEAD `_updateState` 相当）。
/// - [emit]: 現在の状態を無条件にストリームへ発行（HEAD connect() の
///   `_connectionStateController.add(_state)` 相当）。
class SshConnectionStateController {
  SshConnectionState _state = SshConnectionState.disconnected;
  final StreamController<SshConnectionState> _controller =
      StreamController<SshConnectionState>.broadcast();

  /// 現在の接続状態。
  SshConnectionState get state => _state;

  /// 最後のエラーメッセージ（書込は facade の配線クロージャ経由）。
  String? lastError;

  /// 接続状態のストリーム（外部から監視用）。
  Stream<SshConnectionState> get connectionStateStream => _controller.stream;

  /// ストリーム発行なしで状態を代入する。
  void setState(SshConnectionState newState) {
    _state = newState;
  }

  /// 変化時のみストリームへ発行する。
  void transition(SshConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _controller.add(newState);
    }
  }

  /// 現在の状態を無条件にストリームへ発行する。
  void emit() {
    _controller.add(_state);
  }

  /// ストリームを閉じる（dispose 時）。
  Future<void> close() => _controller.close();
}
