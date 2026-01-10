import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/notification_rule.dart';
import '../../providers/notification_provider.dart';
import 'widgets/rule_card.dart';
import 'widgets/rule_form_dialog.dart';

/// 通知ルール一覧画面
class NotificationRulesScreen extends ConsumerStatefulWidget {
  const NotificationRulesScreen({super.key});

  @override
  ConsumerState<NotificationRulesScreen> createState() =>
      _NotificationRulesScreenState();
}

class _NotificationRulesScreenState
    extends ConsumerState<NotificationRulesScreen> {
  @override
  void initState() {
    super.initState();
    // 初回起動時にデフォルトルールを作成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDefaultRules();
    });
  }

  Future<void> _initializeDefaultRules() async {
    final rules = await ref.read(notificationRulesProvider.future);
    if (rules.isEmpty) {
      await ref.read(notificationRulesProvider.notifier).createDefaultRules();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(notificationRulesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Rules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => _showNotificationHistory(context),
            tooltip: 'Notification History',
          ),
        ],
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildErrorView(context, error),
        data: (rules) => _buildRulesList(context, rules),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createRule(context),
        tooltip: 'New Rule',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildRulesList(BuildContext context, List<NotificationRule> rules) {
    if (rules.isEmpty) {
      return _buildEmptyView(context);
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(notificationRulesProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 88),
        itemCount: rules.length,
        itemBuilder: (context, index) {
          final rule = rules[index];
          return RuleCard(
            rule: rule,
            onTap: () => _showRuleDetails(context, rule),
            onEdit: () => _editRule(context, rule),
            onDelete: () => _deleteRule(context, rule),
          );
        },
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No Notification Rules',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create rules to get notified when specific patterns appear in terminal output',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _createRule(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Rule'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(notificationRulesProvider.notifier)
                    .createDefaultRules();
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Use Default Rules'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load rules',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                ref.invalidate(notificationRulesProvider);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRule(BuildContext context) async {
    final result = await RuleFormDialog.show(context);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rule "${result.name}" created')),
      );
    }
  }

  Future<void> _editRule(BuildContext context, NotificationRule rule) async {
    final result = await RuleFormDialog.show(context, existingRule: rule);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rule "${result.name}" updated')),
      );
    }
  }

  Future<void> _deleteRule(BuildContext context, NotificationRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content: Text('Are you sure you want to delete "${rule.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(notificationRulesProvider.notifier).delete(rule.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rule "${rule.name}" deleted')),
        );
      }
    }
  }

  void _showRuleDetails(BuildContext context, NotificationRule rule) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _RuleDetailsSheet(rule: rule),
    );
  }

  void _showNotificationHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const _NotificationHistoryScreen(),
      ),
    );
  }
}

/// ルール詳細シート
class _RuleDetailsSheet extends StatelessWidget {
  const _RuleDetailsSheet({required this.rule});

  final NotificationRule rule;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Row(
              children: [
                Icon(
                  rule.enabled
                      ? Icons.notifications_active
                      : Icons.notifications_off,
                  color: rule.enabled ? colorScheme.primary : colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rule.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),

            if (rule.description != null) ...[
              const SizedBox(height: 8),
              Text(
                rule.description!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // 詳細情報
            _buildDetailRow(context, 'Status', rule.enabled ? 'Enabled' : 'Disabled'),
            _buildDetailRow(context, 'Created', _formatDate(rule.createdAt)),
            if (rule.updatedAt != null)
              _buildDetailRow(context, 'Updated', _formatDate(rule.updatedAt!)),
            if (rule.lastMatchedAt != null)
              _buildDetailRow(context, 'Last Match', _formatDate(rule.lastMatchedAt!)),
            _buildDetailRow(context, 'Match Count', '${rule.matchCount}'),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// 通知履歴画面
class _NotificationHistoryScreen extends ConsumerWidget {
  const _NotificationHistoryScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(notificationEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await ref.read(notificationEventsProvider.notifier).markAllAsRead();
            },
            tooltip: 'Mark All as Read',
          ),
          PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'clear') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear History'),
                    content: const Text(
                      'Are you sure you want to clear all notification history?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await ref.read(notificationEventsProvider.notifier).clearAll();
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep),
                  title: Text('Clear History'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return _NotificationEventTile(event: event);
            },
          );
        },
      ),
    );
  }
}

/// 通知イベントタイル
class _NotificationEventTile extends ConsumerWidget {
  const _NotificationEventTile({required this.event});

  final NotificationEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: Key(event.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(Icons.delete, color: colorScheme.onError),
      ),
      onDismissed: (_) async {
        await ref.read(notificationEventsProvider.notifier).delete(event.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              event.read ? colorScheme.surfaceContainerHighest : colorScheme.primaryContainer,
          child: Icon(
            Icons.notifications,
            color: event.read ? colorScheme.outline : colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          event.ruleName,
          style: TextStyle(
            fontWeight: event.read ? null : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${event.matchedText}"',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${event.connectionName}${event.sessionName != null ? ' • ${event.sessionName}' : ''}',
              style: TextStyle(fontSize: 11, color: colorScheme.outline),
            ),
          ],
        ),
        trailing: Text(
          _formatTime(event.timestamp),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
        ),
        onTap: () async {
          if (!event.read) {
            await ref.read(notificationEventsProvider.notifier).markAsRead(event.id);
          }
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
