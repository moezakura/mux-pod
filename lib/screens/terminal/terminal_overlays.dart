import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/ssh_provider.dart';
import '../../theme/design_colors.dart';
import '../../l10n/l10n_ext.dart';

/// エラーオーバーレイ（接続エラー / ネットワーク待機 / キューイング表示）。
///
/// 再接続ボタンとキューイング状態の表示を持ち、メインのターミナル表示を
/// 覆う。データ（[queuedCount] / [isWaitingForNetwork] / [isReconnecting]）と
/// コールバック（[onRetryNow] / [onClearQueue]）は呼び出し側から注入される。
class ErrorOverlay extends StatelessWidget {
  final String? error;
  final int queuedCount;
  final bool isWaitingForNetwork;
  final bool isReconnecting;
  final VoidCallback onRetryNow;
  final VoidCallback onClearQueue;

  const ErrorOverlay({
    super.key,
    this.error,
    required this.queuedCount,
    required this.isWaitingForNetwork,
    required this.isReconnecting,
    required this.onRetryNow,
    required this.onClearQueue,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: isDark ? Colors.black87 : Colors.white.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWaitingForNetwork ? Icons.signal_wifi_off : Icons.error_outline,
              color: isWaitingForNetwork
                  ? DesignColors.warning
                  : colorScheme.error,
              size: 48,
            ),
            // inventory: LEGACY-0074
            const SizedBox(height: 16),
            // inventory: LEGACY-0090
            Text(
              isWaitingForNetwork
                  ? context.l10n.termWaitingForNetwork
                  : (error ?? context.l10n.termConnectionError),
              style: TextStyle(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),

            // キューイング状態
            if (queuedCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: DesignColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard, size: 16, color: DesignColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.termCharsQueued(queuedCount),
                      style: TextStyle(
                        color: DesignColors.primary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onClearQueue,
                      child: Icon(
                        Icons.clear,
                        size: 16,
                        color: DesignColors.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: onRetryNow,
                  child: Text(context.l10n.termRetryNow),
                ),
                if (isReconnecting) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 接続状態インジケーター（左ボーダー付きのコンテナ）。
///
/// 再接続中は [ReconnectingIndicator]、それ以外はレイテンシ表示を出す。
class ConnectionIndicator extends StatelessWidget {
  final SshState sshState;
  final int queuedCount;
  final int latency;
  final VoidCallback onRetryNow;

  const ConnectionIndicator({
    super.key,
    required this.sshState,
    required this.queuedCount,
    required this.latency,
    required this.onRetryNow,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colorScheme.outline, width: 1)),
      ),
      child: sshState.isReconnecting
          // inventory: TERM-DIALOG-010
          ? ReconnectingIndicator(
              sshState: sshState,
              queuedCount: queuedCount,
              onRetryNow: onRetryNow,
            )
          : LatencyIndicator(latency: latency),
    );
  }
}

// inventory: TERM-DIALOG-009
/// レイテンシ表示
class LatencyIndicator extends StatelessWidget {
  final int latency;

  const LatencyIndicator({super.key, required this.latency});
  @override
  Widget build(BuildContext context) {
    // レイテンシに応じた色を決定
    // inventory: LEGACY-0076
    Color indicatorColor;
    if (latency < 100) {
      indicatorColor = DesignColors.success; // 緑: 良好
    } else if (latency < 300) {
      indicatorColor = DesignColors.primary; // シアン: 普通
    } else if (latency < 500) {
      indicatorColor = DesignColors.warning; // オレンジ: やや遅い
    } else {
      indicatorColor = DesignColors.error; // 赤: 遅い
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bolt,
          size: 10,
          color: indicatorColor.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Text(
          '${latency}ms',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: indicatorColor.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// 再接続中インジケーター
class ReconnectingIndicator extends StatelessWidget {
  final SshState sshState;
  final int queuedCount;
  final VoidCallback onRetryNow;

  const ReconnectingIndicator({
    super.key,
    required this.sshState,
    required this.queuedCount,
    required this.onRetryNow,
  });

  @override
  Widget build(BuildContext context) {
    final attempt = sshState.reconnectAttempt;
    final isWaitingForNetwork = sshState.isWaitingForNetwork;
    final nextRetryAt = sshState.nextRetryAt;

    // 次回リトライまでの秒数を計算
    // inventory: LEGACY-0077
    String? countdownText;
    if (nextRetryAt != null && !isWaitingForNetwork) {
      final remaining = nextRetryAt.difference(DateTime.now()).inSeconds;
      if (remaining > 0) {
        countdownText = '${remaining}s';
      }
    }

    return Row(
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
          isWaitingForNetwork
              ? context.l10n.termOffline
              : context.l10n.termReconnecting +
                    (attempt > 1 ? ' ($attempt)' : ''),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: DesignColors.warning.withValues(alpha: 0.8),
          ),
        ),

        // カウントダウン
        if (countdownText != null) ...[
          const SizedBox(width: 4),
          Text(
            countdownText,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: DesignColors.textMuted,
            ),
          ),
        ],

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
          onTap: onRetryNow,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: DesignColors.warning.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              context.l10n.termRetry,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: DesignColors.warning.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 未接続バナー。
///
/// 特殊キーバー（SpecialKeysBar）の代わりに表示し、未接続（書き込み不可）
/// であることを示す。キー入力が無効なため、デザイン上の注意書きのみを担う。
class DisconnectedBanner extends StatelessWidget {
  final bool isDark;

  const DisconnectedBanner({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDark
          ? DesignColors.connectingCardDark.withValues(alpha: 0.4)
          : DesignColors.connectingCardLight,
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 14,
            color: isDark
                ? DesignColors.connectedCardTextDark
                : DesignColors.connectedCardTextLight,
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.termDisconnectedBanner,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? DesignColors.connectedCardTextDark
                  : DesignColors.connectedCardTextLight,
            ),
          ),
          const Spacer(),
          Text(
            'Herdr',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
