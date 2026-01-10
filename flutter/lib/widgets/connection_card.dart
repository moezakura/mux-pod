import 'package:flutter/material.dart';

import '../models/connection.dart';
import '../services/ssh/ssh_client.dart';

/// 接続カードウィジェット
///
/// 接続情報をカード形式で表示する。
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.connection,
    this.status,
    this.onTap,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
  });

  final Connection connection;
  final ConnectionStatus? status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー: 名前 + ステータス
              Row(
                children: [
                  Expanded(
                    child: Text(
                      connection.name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildStatusIndicator(context),
                ],
              ),
              const SizedBox(height: 8),

              // ホスト情報
              Row(
                children: [
                  Icon(
                    Icons.computer,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${connection.username}@${connection.host}:${connection.port}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // 認証方法
              Row(
                children: [
                  Icon(
                    connection.authMethod.when(
                      password: () => Icons.password,
                      key: (_) => Icons.key,
                    ),
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connection.authMethod.when(
                      password: () => 'Password',
                      key: (keyId) => 'SSH Key',
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  // 最終接続日時
                  if (connection.lastConnected != null) ...[
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatLastConnected(connection.lastConnected!),
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),

              // タグ
              if (connection.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: connection.tags.map((tag) {
                    return Chip(
                      label: Text(tag),
                      labelStyle: textTheme.labelSmall,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],

              // アクションボタン
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        iconSize: 20,
                        onPressed: onEdit,
                        tooltip: 'Edit',
                      ),
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        iconSize: 20,
                        onPressed: onDelete,
                        tooltip: 'Delete',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (status == null) {
      return const SizedBox.shrink();
    }

    final Color color;
    final String label;
    final IconData icon;

    switch (status!) {
      case ConnectionStatus.disconnected:
        color = colorScheme.outline;
        label = 'Disconnected';
        icon = Icons.link_off;
      case ConnectionStatus.connecting:
        color = colorScheme.tertiary;
        label = 'Connecting...';
        icon = Icons.sync;
      case ConnectionStatus.authenticating:
        color = colorScheme.tertiary;
        label = 'Authenticating...';
        icon = Icons.lock_open;
      case ConnectionStatus.connected:
        color = colorScheme.primary;
        label = 'Connected';
        icon = Icons.link;
      case ConnectionStatus.error:
        color = colorScheme.error;
        label = 'Error';
        icon = Icons.error_outline;
    }

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLastConnected(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}
