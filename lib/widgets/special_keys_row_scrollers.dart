import 'package:flutter/widgets.dart';

/// 行水平ScrollController群の所有・行数追従sync・新規トークン位置への
/// 自動スクロール手配（postFrame＋isActiveガード）の所有者。
///
/// ScrollController は行数に合わせて作成・破棄される。isActive は
/// 合成ルート State の `() => mounted` を受け取り、postFrame 実行時の
/// 生存確認に使う（現行の `mounted` ガード相当）。
class SpecialKeysRowScrollers {
  SpecialKeysRowScrollers({required bool Function() isActive})
    : _isActive = isActive;

  final bool Function() _isActive;

  /// 行ごとの水平スクロール制御（新規ボタン追加時にその位置へ自動スクロール）。
  /// 行数は可変なので、行数の変化に合わせて作成・破棄する。
  final List<ScrollController> _controllers = [];

  /// スクロール制御の本数を行数に合わせる（余った分は破棄する）。
  void sync(int rowCount) {
    while (_controllers.length < rowCount) {
      _controllers.add(ScrollController());
    }
    while (_controllers.length > rowCount) {
      _controllers.removeLast().dispose();
    }
  }

  ScrollController controllerAt(int row) => _controllers[row];

  /// 追加されたトークンが行の先頭かどうか（先頭挿入なら true）
  static bool grewAtStart(List<String> before, List<String> after) {
    if (before.isEmpty) return false;
    return after.first != before.first;
  }

  /// 行の水平スクロールを新規ボタンの位置まで移動する
  void scheduleScrollToNewToken(int row, {required bool atStart}) {
    final controller = _controllers[row];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isActive() || !controller.hasClients) return;
      final position = controller.position;
      if (position.maxScrollExtent > 0) {
        controller.animateTo(
          atStart ? 0 : position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
  }
}
