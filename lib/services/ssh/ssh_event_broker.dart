import 'dart:typed_data';

import 'ssh_models.dart';

/// イベント配信の単一所有者。
///
/// [SshEvents] を保持し、setEventHandlers / updateEventHandlers / onData /
/// onClose / onError の発火のみを行う。発火の実体（状態遷移や lastError の
/// 書込）は呼出側（facade の配線クロージャ）が担う。
class SshEventBroker {
  SshEvents _events = const SshEvents();

  /// イベントハンドラを設定する。
  void setEventHandlers(SshEvents events) {
    _events = events;
  }

  /// イベントハンドラを更新する。
  void updateEventHandlers({
    void Function(Uint8List data)? onData,
    void Function()? onClose,
    void Function(Object error)? onError,
  }) {
    _events = _events.copyWith(
      onData: onData,
      onClose: onClose,
      onError: onError,
    );
  }

  /// データ受信を配信する。
  void onData(Uint8List data) {
    _events.onData?.call(data);
  }

  /// 接続クローズを配信する。
  void onClose() {
    _events.onClose?.call();
  }

  /// エラーを配信する。
  void onError(Object error) {
    _events.onError?.call(error);
  }
}
