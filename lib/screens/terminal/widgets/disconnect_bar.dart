import 'package:flutter/material.dart';

import '../../../theme/design_colors.dart';

/// 切断/再接続/エラー状態を示すヘッダー直下の 2px 赤バー。
///
/// タップ不可（状態表示専用）。強制再接続は右上インジケーターの
/// 「再試行」と通信エラーパネルの「今すぐ再接続」アクションの 2 経路で行う。
class DisconnectBar extends StatelessWidget {
  const DisconnectBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 2, color: DesignColors.error);
  }
}
