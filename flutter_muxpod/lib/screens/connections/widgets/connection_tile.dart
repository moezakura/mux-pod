import 'package:flutter/material.dart';

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
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
