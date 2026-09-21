/// resize ダイアログ群の集約 re-export（互換性のための thin re-export）。
///
/// 実装は責務ベース再設計（P2）により `resize/` 配下に分割されている。
/// 本ファイルはロジックを持たず、既存の import 元（terminal_screen.dart /
/// resize_dialog_test.dart）との互換のため公開面（シンボル名・シグネチャ）を
/// 維持する。
///
/// 各シンボルの実装先:
/// - [ResizeResult] → `resize/resize_result.dart`
/// - [HerdrResizePaneDialog] → `resize/herdr_pane_resize_dialog.dart`
/// - [ResizePaneDialog] → `resize/pane_resize_dialog.dart`
/// - [ResizeWindowDialog] → `resize/window_resize_dialog.dart`
/// - [HerdrResizeTerminalDialog] → `resize/herdr_terminal_resize_dialog.dart`
library;

export 'resize/herdr_pane_resize_dialog.dart';
export 'resize/herdr_terminal_resize_dialog.dart';
export 'resize/pane_resize_dialog.dart';
export 'resize/resize_result.dart';
export 'resize/window_resize_dialog.dart';
