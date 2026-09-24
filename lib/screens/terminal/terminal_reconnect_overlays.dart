// P4/#125: 切断UXのオーバーレイ部品。
//
// 通信エラーパネル（画面下部）と再接続詳細パネル（ヘッダー直下）を、
// シェル（terminal_view_shell.dart）から切り出した責務単位のウィジェット。
// 状態は root State（TerminalReconnectPanelController 経由）が所有し、
// 本ファイルは props のみを受け取る。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'widgets/comm_error_panel.dart';
import 'widgets/reconnect_detail_panel.dart';

/// 通信エラーパネル（下からスライドしてフェードイン）。
///
/// 切断検知・初期接続エラー時に表示し、× 押下または接続復帰で閉じるまで
/// 表示し続ける。
class TerminalCommErrorOverlay extends StatelessWidget {
  final String? title;
  final String? body;
  final String? detail;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const TerminalCommErrorOverlay({
    super.key,
    required this.title,
    required this.body,
    required this.detail,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 64,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.35,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.bottomCenter,
            children: [...previousChildren, ?currentChild],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: body != null
              ? CommErrorPanel(
                  title: title ?? '',
                  body: body ?? '',
                  detail: detail ?? '',
                  expanded: expanded,
                  onToggleExpanded: onToggleExpanded,
                  onRetry: onRetry,
                  onClose: onClose,
                )
              : const SizedBox(width: double.infinity),
        ),
      ),
    );
  }
}

/// 再接続詳細パネル（ヘッダーの ReconnectingIndicator タップで開閉）。
///
/// [headerLink] でヘッダー下端に追従させる。
class TerminalReconnectDetailOverlay extends StatelessWidget {
  final LayerLink headerLink;
  final bool visible;
  final bool isReconnecting;
  final ValueListenable<int?> countdown;
  final int attempt;
  final double arrowRight;

  const TerminalReconnectDetailOverlay({
    super.key,
    required this.headerLink,
    required this.visible,
    required this.isReconnecting,
    required this.countdown,
    required this.attempt,
    required this.arrowRight,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: CompositedTransformFollower(
        link: headerLink,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(-16, 2),
        child: IgnorePointer(
          ignoring: !visible || !isReconnecting,
          child: AnimatedSwitcher(
            key: const ValueKey('reconnect_tooltip_transition'),
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.topRight,
              children: [...previousChildren, ?currentChild],
            ),
            child: visible && isReconnecting
                ? ReconnectDetailPanel(
                    key: const ValueKey('reconnect_details'),
                    countdown: countdown,
                    attempt: attempt,
                    visible: true,
                    arrowRight: arrowRight,
                    width: (MediaQuery.sizeOf(context).width - 32)
                        .clamp(0, 264)
                        .toDouble(),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('reconnect_details_hidden'),
                  ),
          ),
        ),
      ),
    );
  }
}
