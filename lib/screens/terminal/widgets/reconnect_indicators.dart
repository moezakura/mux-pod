import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../theme/design_colors.dart';

/// 切断中インジケーター（初期接続失敗時などに表示）。
///
/// エラー文言は通信エラーパネルへ移行したためここには入れない。
/// キュー件数と強制再接続の導線のみをコンパクトに表示する。
class DisconnectedIndicator extends StatelessWidget {
  /// 送信待ちキューの件数。
  final int queuedCount;

  /// 「再試行」（reconnectNow）タップ処理。
  final VoidCallback onReconnectNow;

  const DisconnectedIndicator({
    super.key,
    required this.queuedCount,
    required this.onReconnectNow,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 切断アイコン
        Icon(
          Icons.link_off,
          size: 12,
          color: DesignColors.error.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),

        // ステータステキスト
        Text(
          context.l10n.termDisconnected,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: DesignColors.error.withValues(alpha: 0.8),
          ),
        ),

        // キューイング状態
        if (queuedCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: DesignColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              context.l10n.termChars(queuedCount),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: DesignColors.primary,
              ),
            ),
          ),
        ],

        // 今すぐ再接続ボタン
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onReconnectNow,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: DesignColors.error.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              context.l10n.termRetry,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: DesignColors.error,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 再接続中インジケーター。
///
/// ヘッダー右側の空間を圧迫しないよう表示はコンパクトに保つ。
/// - 接続処理中: `${スピナー} Reconnecting (N)`（N は試行回数・2 回目から表示）
/// - 自動再接続待機中: `${スピナー} Ns (C)`（N は残り秒のカウントダウン、
///   C は試行回数）。毎秒更新は [countdown] 経由。
/// - ネットワーク断: `${圏外アイコン} Offline`
/// タップで再接続詳細パネル（カウントダウン + 試行回数）を開閉する。
/// 「Reconnecting」の文字は接続処理中のみ出る（待機中はカウントダウンのみ）。
class ReconnectingIndicator extends StatelessWidget {
  /// 自動再接続待機中の残り秒（null = 非表示）。
  final ValueListenable<int?> countdown;

  /// ネットワーク断（Offline 表示）中かどうか。
  final bool isWaitingForNetwork;

  /// 再接続の試行回数。
  final int attempt;

  /// タップ処理（再接続詳細パネルの開閉トグル）。
  final VoidCallback onTap;

  const ReconnectingIndicator({
    super.key,
    required this.countdown,
    required this.isWaitingForNetwork,
    required this.attempt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: countdown,
      builder: (context, remainingSeconds, _) {
        final isWaitingForRetry =
            remainingSeconds != null && !isWaitingForNetwork;

        // ステータステキスト（接続処理中のみ「Reconnecting」を出す）
        final String statusText;
        if (isWaitingForNetwork) {
          statusText = context.l10n.termOffline;
        } else if (isWaitingForRetry) {
          statusText = '${remainingSeconds}s ($attempt)';
        } else {
          statusText =
              context.l10n.termReconnecting +
              (attempt > 1 ? ' ($attempt)' : '');
        }

        final Widget content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // スピナーまたは圏外アイコン
            if (isWaitingForNetwork)
              Icon(
                Icons.signal_wifi_off,
                size: 12,
                color: DesignColors.warning.withValues(alpha: 0.8),
              )
            else
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: DesignColors.warning.withValues(alpha: 0.8),
                ),
              ),
            const SizedBox(width: 6),

            // ステータステキスト
            Text(
              statusText,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: DesignColors.warning.withValues(alpha: 0.8),
              ),
            ),
          ],
        );

        // ネットワーク断中は「Offline」と表示済みのためパネルは省略。
        // タップで再接続詳細パネル（カウントダウン + 試行回数）を開閉する。
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        );
      },
    );
  }
}
