/// P3: 実装は `connection_list_screen.dart` へ移動（責務ベース分割）。
///
/// 公開面（[ConnectionsScreen]）を安定供給する compat layer（ロジックなし）。
/// 呼出元（home_screen.dart・テスト）の import パスは変わらない。
/// 注: 分割で public 化した `ConnectionCard` 等は import 経由のため
/// 再 export されない（Dart は import を再 export しない）→ シム経由で
/// 外部へ漏れない。
/// 相互循環防止: `currentTabProvider` は home_screen.dart ではなく中立
/// モジュール `navigation/current_tab_provider.dart` を参照する。
library;

export 'connection_list_screen.dart';
