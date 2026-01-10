import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/key_provider.dart';
import '../../router/app_router.dart';
import '../../widgets/key_card.dart';

/// SSH鍵一覧画面
class KeysScreen extends ConsumerWidget {
  const KeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keysAsync = ref.watch(keysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Keys'),
      ),
      body: keysAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load keys',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.invalidate(keysProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (keys) {
          if (keys.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(keysProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                return KeyCard(
                  sshKey: key,
                  onTap: () => _showKeyDetails(context, key.id),
                  onDelete: () => _confirmDelete(context, ref, key.id, key.name),
                  onSetDefault: () => _setDefault(context, ref, key.id),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddKeyOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Key'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.key_off,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'No SSH Keys',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Generate or import an SSH key to use key-based authentication',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddKeyOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Generate New Key'),
                subtitle: const Text('Create a new SSH key pair'),
                onTap: () {
                  Navigator.pop(context);
                  context.push(AppRoutes.keyGenerate);
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Import Existing Key'),
                subtitle: const Text('Import a private key from file or text'),
                onTap: () {
                  Navigator.pop(context);
                  context.push(AppRoutes.keyImport);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showKeyDetails(BuildContext context, String keyId) {
    // TODO: 鍵詳細画面への遷移
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Key details: $keyId')),
    );
  }

  void _setDefault(BuildContext context, WidgetRef ref, String keyId) async {
    await ref.read(keysProvider.notifier).setDefault(keyId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default key updated')),
      );
    }
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String keyId,
    String keyName,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete SSH Key'),
          content: Text('Are you sure you want to delete "$keyName"?\n\n'
              'This will remove the private key permanently.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await ref.read(keysProvider.notifier).delete(keyId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Key deleted')),
                  );
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
