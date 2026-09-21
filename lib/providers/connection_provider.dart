/// 接続設定関連の公開面を供給する compat layer。
///
/// 実装は責務ごとに以下のファイルへ移動済みのため、ここでは re-export のみ
/// 行う（ロジックは持たない）。
///
/// - モデル: `connection.dart`
/// - 状態: `connections_state.dart`
/// - 永続化: `connection_storage.dart`
/// - 管理（Notifier）: `connections_notifier.dart`
/// - UI状態: `connection_ui_state.dart`
/// - 派生ビュー: `connection_selectors.dart`
library;

export 'connection.dart';
export 'connection_selectors.dart';
export 'connection_storage.dart';
export 'connection_ui_state.dart';
export 'connections_notifier.dart';
export 'connections_state.dart';
