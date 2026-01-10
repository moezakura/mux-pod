import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_rule.dart';
import '../providers/notification_provider.dart';

/// 通知オーバーレイ
///
/// 画面上部にスライドイン/アウトする通知バナーを表示する。
class NotificationOverlay extends ConsumerStatefulWidget {
  const NotificationOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<NotificationOverlay> createState() =>
      _NotificationOverlayState();
}

class _NotificationOverlayState extends ConsumerState<NotificationOverlay> {
  final List<NotificationEvent> _visibleNotifications = [];
  StreamSubscription<NotificationEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribeToNotifications();
  }

  void _subscribeToNotifications() {
    final engine = ref.read(notificationEngineProvider);
    _subscription = engine.events.listen(_onNewNotification);
  }

  void _onNewNotification(NotificationEvent event) {
    setState(() {
      _visibleNotifications.add(event);
    });

    // 5秒後に自動で消す
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _visibleNotifications.remove(event);
        });
      }
    });
  }

  void _dismissNotification(NotificationEvent event) {
    setState(() {
      _visibleNotifications.remove(event);
    });
    ref.read(notificationEventsProvider.notifier).markAsRead(event.id);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // 通知バナー
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Column(
            children: _visibleNotifications.map((event) {
              return _NotificationBanner(
                key: ValueKey(event.id),
                event: event,
                onDismiss: () => _dismissNotification(event),
                onTap: () => _dismissNotification(event),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// 通知バナー
class _NotificationBanner extends StatefulWidget {
  const _NotificationBanner({
    super.key,
    required this.event,
    required this.onDismiss,
    required this.onTap,
  });

  final NotificationEvent event;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dismissible(
          key: ValueKey(widget.event.id),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => widget.onDismiss(),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // アイコン
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.notifications,
                          color: colorScheme.onPrimary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // コンテンツ
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.event.ruleName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '"${_truncateText(widget.event.matchedText, 50)}"',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.event.connectionName,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 閉じるボタン
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                          size: 20,
                        ),
                        onPressed: widget.onDismiss,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

/// 通知バッジ
///
/// 未読通知数を表示する小さなバッジ。
class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({
    super.key,
    required this.child,
    this.offset = Offset.zero,
  });

  final Widget child;
  final Offset offset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: offset.dx - 4,
            top: offset.dy - 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

/// 通知スナックバー
///
/// 画面下部に表示されるシンプルな通知。
void showNotificationSnackBar(
  BuildContext context,
  NotificationEvent event, {
  VoidCallback? onTap,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.notifications, color: colorScheme.onPrimary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.ruleName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '"${event.matchedText}"',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: colorScheme.primary,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      action: onTap != null
          ? SnackBarAction(
              label: 'View',
              textColor: colorScheme.onPrimary,
              onPressed: onTap,
            )
          : null,
    ),
  );
}
