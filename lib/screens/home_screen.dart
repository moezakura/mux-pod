/// ホーム画面（Bottom Navigation 付き）の公開面を供給する thin re-export シム。
///
/// 責務分割（P3 責務ベース再設計）のため、実装本体は配下へ移設済み:
/// - `home/home_screen.dart`: 5 タブの IndexedStack 合成ルート（画面本体）
/// - `home/widgets/home_bottom_nav_bar.dart`: ボトムナビゲーションバー
/// - `../navigation/current_tab_provider.dart`: タブ状態（中立モジュール）
///
/// タブ状態は中立モジュールへ移設した。画面間の相互循環参照を防ぐため、
/// タブ状態が必要な画面（connections / keys / settings 等）は本ファイルでは
/// なく中立モジュールを直接 import すること。
library;

export '../navigation/current_tab_provider.dart';
export 'home/home_screen.dart' show HomeScreen;
