import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart' show settingsProvider;
import '../../../services/tmux/pane_navigator.dart' show SwipeDirection;
import 'terminal_input_ports.dart'
    show TerminalInputCapabilities, TerminalNavigationPort;

/// 2 本指スワイプのディスパッチと `navigableDirections` の計算（V5）。
///
/// ヘッド（`_handleTwoFingerSwipe` / `_getNavigableDirections`）の tmux / herdr
/// 分岐を [TerminalNavigationPort] 越しに維持する。herdr 固有の番号解決
/// （`pane focus --direction` / レイアウト矩形の隣接判定）は port の実装側
/// （herdr navigation API）が行う。自領域の state は持たない（純ディスパッチャ）。
class TerminalNavigationController {
  TerminalNavigationController({
    required this.ref,
    required this.caps,
    required this.nav,
  });

  final WidgetRef ref;
  final TerminalInputCapabilities caps;
  final TerminalNavigationPort nav;

  /// 2 本指スワイプによるペイン切り替え（TERM-NAV-003）。
  void handleTwoFingerSwipe(SwipeDirection direction) {
    // 方向フォーカス不可時は送信しない（R3: herdr で tmuxProvider を読まない）。
    if (!caps.canFocusDirection) return;
    if (nav.isHerdr) {
      // ignore: unawaited_futures
      nav.focusPaneDirection(direction);
      return;
    }
    final settings = ref.read(settingsProvider);
    // ignore: unawaited_futures
    nav.selectAdjacentPane(direction, invert: settings.invertPaneNavigation);
  }

  /// 現在のペインからナビゲーション可能な方向（TERM-NAV-007）。
  Map<SwipeDirection, bool>? navigableDirections() {
    if (!caps.canFocusDirection) return null;
    final settings = ref.read(settingsProvider);
    return nav.navigableDirections(invert: settings.invertPaneNavigation);
  }
}
