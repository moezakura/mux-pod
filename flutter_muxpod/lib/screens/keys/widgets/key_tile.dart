import 'package:flutter/material.dart';

/// SSH鍵のタイルWidget
class KeyTile extends StatelessWidget {
  final String name;
  final String type;
  final String fingerprint;
  final DateTime createdAt;
  final VoidCallback? onCopyPublicKey;
  final VoidCallback? onDelete;

  const KeyTile({
    super.key,
    required this.name,
    required this.type,
    required this.fingerprint,
    required this.createdAt,
    this.onCopyPublicKey,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Icon(
          type.toLowerCase() == 'ed25519' ? Icons.security : Icons.vpn_key,
        ),
      ),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type.toUpperCase()),
          Text(
            fingerprint,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'copy':
              onCopyPublicKey?.call();
            case 'delete':
              onDelete?.call();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'copy',
            child: Row(
              children: [
                Icon(Icons.copy),
                SizedBox(width: 8),
                Text('Copy Public Key'),
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
    );
  }
}
