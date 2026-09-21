/// アクティブセッション関連の公開面を供給する compat layer。
///
/// 実装は責務ごとに以下のファイルへ移動済みのため、ここでは re-export のみ
/// 行う（ロジックは持たない）。
///
/// - モデル: `active_session.dart`
/// - 状態: `active_sessions_state.dart`
/// - 永続化: `active_sessions_storage.dart`
/// - 差分マージ: `active_sessions_merger.dart`
/// - 管理（Notifier）: `active_sessions_notifier.dart`
library;

export 'active_session.dart';
export 'active_sessions_merger.dart';
export 'active_sessions_notifier.dart';
export 'active_sessions_state.dart';
export 'active_sessions_storage.dart';
