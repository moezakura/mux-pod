import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../theme/design_colors.dart';

/// 再接続詳細パネル（カウントダウン表示の直下に開く）。
///
/// ヘッダー: スピナー + 「再接続中」 / 「次の再接続まで」「再接続の試行回数」
/// の 2 行 / 区切り線 + 自動再試行の説明。右上にはカウントダウン表示を
/// 指す矢印突起を描画する。残り秒は毎秒更新される（[countdown] 経由）。
class ReconnectDetailPanel extends StatelessWidget {
  /// 自動再接続待機中の残り秒（null = 接続処理中）。
  final ValueListenable<int?> countdown;

  /// 再接続の試行回数。
  final int attempt;

  /// 表示中かどうか（非表示時はスピナー静止で構築し、pumpAndSettle が
  /// 永久に完了しないのを防ぐ）。
  final bool visible;

  const ReconnectDetailPanel({
    super.key,
    required this.countdown,
    required this.attempt,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    const panelColor = Color(0xFF23242E);
    final remaining = countdown.value ?? 0;
    return ValueListenableBuilder<int?>(
      valueListenable: countdown,
      builder: (context, currentRemaining, _) {
        final seconds = currentRemaining ?? remaining;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 264,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: panelColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー: スピナー + 再接続中（非表示時はスピナー静止で構築し、
                  // pumpAndSettle が永久に完了しないのを防ぐ）
                  Row(
                    children: [
                      if (visible)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DesignColors.secondary,
                          ),
                        )
                      else
                        const SizedBox(width: 14, height: 14),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.termReconnectingPanelTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _panelRow(
                    context,
                    context.l10n.termNextReconnectLabel,
                    context.l10n.termSecondsValue(seconds),
                  ),
                  _panelRow(
                    context,
                    context.l10n.termAttemptsLabel,
                    context.l10n.termAttemptsValue(attempt),
                  ),
                  const Divider(
                    height: 18,
                    thickness: 0.8,
                    color: DesignColors.borderDark,
                  ),
                  Text(
                    context.l10n.termAutoRetryNote,
                    style: const TextStyle(
                      color: DesignColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // カウントダウン表示を指す矢印突起
            Positioned(
              right: 44,
              top: 3,
              child: RotationTransition(
                turns: const AlwaysStoppedAnimation(0.125),
                child: Container(width: 14, height: 14, color: panelColor),
              ),
            ),
          ],
        );
      },
    );
  }

  /// パネル内の「ラベル ... 値」行。
  Widget _panelRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: DesignColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
