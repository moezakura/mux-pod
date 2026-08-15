import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';

/// 接続一覧のタイルWidget
class ConnectionTile extends StatelessWidget {
  final String name;
  final String host;
  final int port;
  final String username;
  final bool isConnected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ConnectionTile({
    super.key,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.isConnected = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isConnected
            ? Colors.green
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.computer,
          color: isConnected
              ? Colors.white
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(name),
      subtitle: Text('$username@$host:$port'),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit?.call();
            case 'delete':
              onDelete?.call();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit),
                const SizedBox(width: 8),
                Text(context.l10n.connEdit),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  context.l10n.connDelete,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
