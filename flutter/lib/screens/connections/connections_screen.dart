import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/connection.dart';
import '../../providers/connection_provider.dart';
import '../../providers/ssh_provider.dart';
import '../../router/app_router.dart';
import '../../widgets/connection_card.dart';

/// 接続一覧画面
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsAsync = ref.watch(connectionsProvider);
    // connectionStateProvider is used to trigger rebuild when connection state changes
    ref.watch(connectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            onPressed: () => context.push(AppRoutes.keys),
            tooltip: 'SSH Keys',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push(AppRoutes.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: connectionsAsync.when(
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
                'Failed to load connections',
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
                onPressed: () => ref.invalidate(connectionsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (connections) {
          if (connections.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(connectionsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: connections.length,
              itemBuilder: (context, index) {
                final connection = connections[index];
                return _ConnectionCardWrapper(
                  connection: connection,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.connectionNew),
        icon: const Icon(Icons.add),
        label: const Text('New Connection'),
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
              Icons.computer_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'No Connections',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a new SSH connection to get started',
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
}

/// ConnectionCardのラッパー（状態管理用）
class _ConnectionCardWrapper extends ConsumerWidget {
  const _ConnectionCardWrapper({
    required this.connection,
  });

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 接続状態を監視
    final sshClient = ref.watch(sshClientProvider);
    final status = sshClient.getStatus(connection.id);

    return ConnectionCard(
      connection: connection,
      status: status,
      onTap: () => _onConnect(context, ref),
      onLongPress: () => _showOptionsMenu(context, ref),
      onEdit: () => context.push('/connection/${connection.id}'),
      onDelete: () => _confirmDelete(context, ref),
    );
  }

  void _onConnect(BuildContext context, WidgetRef ref) {
    context.push('/terminal/${connection.id}');
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.terminal),
                title: const Text('Connect'),
                onTap: () {
                  Navigator.pop(context);
                  _onConnect(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/connection/${connection.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Duplicate'),
                onTap: () {
                  Navigator.pop(context);
                  _duplicate(context, ref);
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _duplicate(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(connectionsProvider.notifier);
    await notifier.add(
      name: '${connection.name} (copy)',
      host: connection.host,
      port: connection.port,
      username: connection.username,
      authMethod: connection.authMethod,
      keyId: connection.keyId,
      timeout: connection.timeout,
      keepAliveInterval: connection.keepAliveInterval,
      tags: connection.tags,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection duplicated')),
      );
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Connection'),
          content: Text('Are you sure you want to delete "${connection.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await ref.read(connectionsProvider.notifier).delete(connection.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Connection deleted')),
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
