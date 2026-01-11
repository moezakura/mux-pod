import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/key_provider.dart';
import '../home_screen.dart';
import 'key_generate_screen.dart';
import 'key_import_screen.dart';
import 'widgets/key_tile.dart';

/// SSH鍵一覧画面
class KeysScreen extends ConsumerWidget {
  const KeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keysState = ref.watch(keysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Keys'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () => ref.read(currentTabProvider.notifier).setTab(3),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _buildBody(context, ref, keysState),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_add_ssh_key',
        onPressed: () {
          _showAddKeyOptions(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, KeysState state) {
    // ローディング中
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // エラー
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Error: ${state.error}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                ref.read(keysProvider.notifier).reload();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // 空状態
    if (state.keys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.vpn_key_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No SSH keys yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to generate or import a key',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    // 鍵一覧
    return ListView.builder(
      itemCount: state.keys.length,
      itemBuilder: (context, index) {
        final keyMeta = state.keys[index];
        return KeyTile(
          keyMeta: keyMeta,
          onCopyPublicKey: () {
            _copyPublicKey(context, keyMeta);
          },
          onDelete: () {
            _showDeleteConfirmation(context, ref, keyMeta);
          },
        );
      },
    );
  }

  void _copyPublicKey(BuildContext context, SshKeyMeta keyMeta) {
    if (keyMeta.publicKey != null) {
      Clipboard.setData(ClipboardData(text: keyMeta.publicKey!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public key copied to clipboard')),
      );
    }
  }

  void _showDeleteConfirmation(
      BuildContext context, WidgetRef ref, SshKeyMeta keyMeta) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Key?'),
        content: Text(
          'Are you sure you want to delete "${keyMeta.name}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteKey(context, ref, keyMeta);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteKey(
      BuildContext context, WidgetRef ref, SshKeyMeta keyMeta) async {
    try {
      final storage = ref.read(secureStorageProvider);
      final keysNotifier = ref.read(keysProvider.notifier);

      // SecureStorageから秘密鍵を削除
      await storage.deletePrivateKey(keyMeta.id);

      // パスフレーズがあれば削除
      if (keyMeta.hasPassphrase) {
        await storage.deletePassphrase(keyMeta.id);
      }

      // メタデータを削除
      await keysNotifier.remove(keyMeta.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Key "${keyMeta.name}" deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete key: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showAddKeyOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle),
              title: const Text('Generate New Key'),
              subtitle: const Text('Create a new RSA or Ed25519 key'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const KeyGenerateScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Import Key'),
              subtitle: const Text('Import an existing private key'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const KeyImportScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
