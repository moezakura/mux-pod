import 'package:flutter/material.dart';

import '../../../providers/key_provider.dart';

/// SSH鍵を表示するタイルウィジェット
class KeyTile extends StatelessWidget {
  final SshKeyMeta keyMeta;
  final VoidCallback? onTap;
  final VoidCallback? onCopyPublicKey;
  final VoidCallback? onDelete;

  const KeyTile({
    super.key,
    required this.keyMeta,
    this.onTap,
    this.onCopyPublicKey,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Icon(_getKeyTypeIcon()),
      ),
      title: Text(keyMeta.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _getKeyTypeLabel(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              _buildSourceBadge(context),
              if (keyMeta.hasPassphrase) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.lock,
                  size: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ],
          ),
          if (keyMeta.fingerprint != null) ...[
            const SizedBox(height: 2),
            Text(
              keyMeta.fingerprint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.outline,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
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
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
        ],
      ),
      isThreeLine: keyMeta.fingerprint != null,
      onTap: onTap,
    );
  }

  IconData _getKeyTypeIcon() {
    if (keyMeta.type.contains('ed25519')) {
      return Icons.vpn_key;
    } else if (keyMeta.type.contains('rsa')) {
      return Icons.key;
    }
    return Icons.security;
  }

  String _getKeyTypeLabel() {
    if (keyMeta.type == 'ed25519') {
      return 'Ed25519';
    } else if (keyMeta.type.startsWith('rsa-')) {
      final bits = keyMeta.type.split('-').last;
      return 'RSA $bits';
    }
    return keyMeta.type.toUpperCase();
  }

  Widget _buildSourceBadge(BuildContext context) {
    final isGenerated = keyMeta.source == KeySource.generated;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isGenerated
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isGenerated ? 'Generated' : 'Imported',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: isGenerated
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSecondaryContainer,
            ),
      ),
    );
  }
}
