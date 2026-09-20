import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../theme/design_colors.dart';

/// 通信エラーパネル（画面下部固定）。
///
/// 赤枠の角丸パネル。ヘッダー行: 「⚠ 通信エラー」+ 詳細展開トグル +
/// 「今すぐ再接続」+「×」。折りたたみ時はタイトル行のみ表示し、
/// 展開すると本文と例外詳細をスクロールして読める。
///
/// 表示/折りたたみの状態は親が保持し（[expanded] / [onToggleExpanded]）、
/// パネル自身は描画のみを担う。
class CommErrorPanel extends StatelessWidget {
  /// 展開時に表示する本文（例: 「サーバーとの接続が切断されました。」）。
  final String body;

  final String title;

  /// 展開したときに表示する例外詳細。
  final String detail;

  /// 例外詳細を展開表示しているかどうか。
  final bool expanded;

  /// 詳細展開トグルのタップ処理。
  final VoidCallback onToggleExpanded;

  /// 「今すぐ再接続」タップ処理。
  final VoidCallback onRetry;

  /// 「×」タップ処理。
  final VoidCallback onClose;

  const CommErrorPanel({
    super.key,
    required this.body,
    required this.title,
    required this.detail,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('comm_error_panel'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesignColors.error, width: 1.2),
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
          // ヘッダー行: ⚠ 通信エラー [▾] ... 今すぐ再接続 [×]
          Row(
            children: [
              // タイトル+詳細展開トグル（タップ領域を広めに取る）
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleExpanded,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: DesignColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: DesignColors.textSecondary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 今すぐ再接続
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    context.l10n.termReconnectNow,
                    style: TextStyle(
                      color: DesignColors.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // × 閉じる
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    color: DesignColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const Divider(color: DesignColors.borderDark, height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  '$body\n$detail',
                  style: const TextStyle(
                    color: DesignColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
