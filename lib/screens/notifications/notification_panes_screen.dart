/// 通知ペイン一覧画面の公開面を供給する thin re-export シム。
///
/// 責務分割（P3 責務ベース再設計）のため、実装本体は配下へ移設済み:
/// - `panes/notification_panes_view.dart`: 画面ルート + 単一状態所有者
/// - `panes/alert_pane_card.dart`: アラートペインカードの表示
/// - `panes/alert_flag_style.dart`: TmuxWindowFlag → 見た目 の純関数
library;

export 'panes/notification_panes_view.dart' show NotificationPanesScreen;
