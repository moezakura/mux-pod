import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/enums.dart';
import '../../../models/notification_rule.dart';
import '../../../providers/notification_provider.dart';
import '../../../services/notification/pattern_matcher.dart';

/// 通知ルールカード
class RuleCard extends ConsumerWidget {
  const RuleCard({
    super.key,
    required this.rule,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final NotificationRule rule;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final patternMatcher = ref.read(patternMatcherProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー
              Row(
                children: [
                  // 有効/無効アイコン
                  _EnabledToggle(
                    enabled: rule.enabled,
                    onChanged: (enabled) async {
                      await ref
                          .read(notificationRulesProvider.notifier)
                          .setEnabled(rule.id, enabled);
                    },
                  ),
                  const SizedBox(width: 12),
                  // ルール名
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: rule.enabled
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                        ),
                        if (rule.description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            rule.description!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // アクションメニュー
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          onEdit?.call();
                        case 'delete':
                          onDelete?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete, color: colorScheme.error),
                          title: Text('Delete', style: TextStyle(color: colorScheme.error)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // パターン条件
              _ConditionChips(
                conditions: rule.conditions,
                patternMatcher: patternMatcher,
              ),

              const SizedBox(height: 12),

              // アクション・頻度・スコープ
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  // アクション
                  ...rule.actions.map((action) => _ActionChip(action: action)),
                  // 頻度
                  _FrequencyChip(frequency: rule.frequency),
                  // スコープ
                  if (rule.scope != RuleScope.global)
                    _ScopeChip(scope: rule.scope),
                ],
              ),

              // マッチ統計
              if (rule.matchCount > 0) ...[
                const SizedBox(height: 12),
                _MatchStats(
                  matchCount: rule.matchCount,
                  lastMatchedAt: rule.lastMatchedAt,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 有効/無効トグル
class _EnabledToggle extends StatelessWidget {
  const _EnabledToggle({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          enabled ? Icons.notifications_active : Icons.notifications_off,
          color: enabled
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 条件チップ
class _ConditionChips extends StatelessWidget {
  const _ConditionChips({
    required this.conditions,
    required this.patternMatcher,
  });

  final List<NotificationCondition> conditions;
  final PatternMatcher patternMatcher;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: conditions.map((condition) {
        final icon = _getPatternTypeIcon(condition.patternType);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colorScheme.onSecondaryContainer),
              const SizedBox(width: 6),
              Text(
                '"${condition.pattern}"',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _getPatternTypeIcon(PatternType type) {
    switch (type) {
      case PatternType.text:
        return Icons.text_fields;
      case PatternType.regex:
        return Icons.code;
      case PatternType.wildcard:
        return Icons.star;
    }
  }
}

/// アクションチップ
class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action});

  final NotificationAction action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (icon, label) = switch (action) {
      NotificationAction.inApp => (Icons.notifications, 'In-app'),
      NotificationAction.sound => (Icons.volume_up, 'Sound'),
      NotificationAction.vibrate => (Icons.vibration, 'Vibrate'),
    };

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.surfaceContainerHighest,
    );
  }
}

/// 頻度チップ
class _FrequencyChip extends StatelessWidget {
  const _FrequencyChip({required this.frequency});

  final NotificationFrequency frequency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (icon, label) = switch (frequency) {
      NotificationFrequency.always => (Icons.repeat, 'Always'),
      NotificationFrequency.oncePerSession => (Icons.looks_one, 'Once/session'),
      NotificationFrequency.oncePerMatch => (Icons.filter_1, 'Once/match'),
    };

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.surfaceContainerHighest,
    );
  }
}

/// スコープチップ
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.scope});

  final RuleScope scope;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (icon, label) = switch (scope) {
      RuleScope.global => (Icons.public, 'Global'),
      RuleScope.connection => (Icons.link, 'Connection'),
      RuleScope.session => (Icons.terminal, 'Session'),
    };

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.tertiaryContainer,
    );
  }
}

/// マッチ統計
class _MatchStats extends StatelessWidget {
  const _MatchStats({
    required this.matchCount,
    required this.lastMatchedAt,
  });

  final int matchCount;
  final DateTime? lastMatchedAt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(Icons.check_circle, size: 14, color: colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          '$matchCount matches',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
        ),
        if (lastMatchedAt != null) ...[
          const SizedBox(width: 12),
          Icon(Icons.schedule, size: 14, color: colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            _formatLastMatch(lastMatchedAt!),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ],
    );
  }

  String _formatLastMatch(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.month}/${date.day}';
  }
}
