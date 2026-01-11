import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/notification_provider.dart';
import '../../services/notification/notification_engine.dart';

/// 通知ルール一覧画面
class NotificationRulesScreen extends ConsumerWidget {
  const NotificationRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Rules'),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.rules.isEmpty
              ? const Center(child: Text('No notification rules yet'))
              : ListView.builder(
                  itemCount: state.rules.length,
                  itemBuilder: (context, index) {
                    final rule = state.rules[index];
                    return _RuleListItem(
                      rule: rule,
                      onTap: () => _showEditRuleDialog(context, ref, rule),
                      onToggle: () {
                        ref.read(notificationProvider.notifier).toggleRule(rule.id);
                      },
                      onDelete: () => _confirmDelete(context, ref, rule),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddRuleDialog(context, ref);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => _RuleFormDialog(ref: ref),
    );
  }

  void _showEditRuleDialog(BuildContext context, WidgetRef ref, NotificationRule rule) {
    showDialog(
      context: context,
      builder: (context) => _RuleFormDialog(ref: ref, existingRule: rule),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, NotificationRule rule) async {
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(notificationProvider.notifier).removeRule(rule.id);
    }
  }
}

/// ルールリストアイテム
class _RuleListItem extends StatelessWidget {
  final NotificationRule rule;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _RuleListItem({
    required this.rule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(rule.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // Handle delete via callback
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        title: Text(
          rule.name,
          style: TextStyle(
            color: rule.enabled ? null : Theme.of(context).disabledColor,
          ),
        ),
        subtitle: Text(
          rule.pattern,
          style: TextStyle(
            fontFamily: 'monospace',
            color: rule.enabled ? null : Theme.of(context).disabledColor,
          ),
        ),
        leading: Icon(
          rule.isRegex ? Icons.code : Icons.text_fields,
          color: rule.enabled ? null : Theme.of(context).disabledColor,
        ),
        trailing: Switch(
          value: rule.enabled,
          onChanged: (_) => onToggle(),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// ルール作成・編集ダイアログ
class _RuleFormDialog extends StatefulWidget {
  final WidgetRef ref;
  final NotificationRule? existingRule;

  const _RuleFormDialog({
    required this.ref,
    this.existingRule,
  });

  @override
  State<_RuleFormDialog> createState() => _RuleFormDialogState();
}

class _RuleFormDialogState extends State<_RuleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _patternController;
  late bool _isRegex;
  late bool _vibrate;

  bool get _isEditing => widget.existingRule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.existingRule;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _patternController = TextEditingController(text: rule?.pattern ?? '');
    _isRegex = rule?.isRegex ?? false;
    _vibrate = rule?.vibrate ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Rule' : 'New Rule'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Build Complete',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _patternController,
                decoration: const InputDecoration(
                  labelText: 'Pattern',
                  hintText: 'error|warning',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a pattern';
                  }
                  if (_isRegex) {
                    try {
                      RegExp(value);
                    } catch (e) {
                      return 'Invalid regex pattern';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Use Regex'),
                value: _isRegex,
                onChanged: (value) {
                  setState(() {
                    _isRegex = value;
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Vibrate'),
                value: _vibrate,
                onChanged: (value) {
                  setState(() {
                    _vibrate = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final rule = NotificationRule(
        id: widget.existingRule?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        pattern: _patternController.text,
        isRegex: _isRegex,
        vibrate: _vibrate,
        enabled: widget.existingRule?.enabled ?? true,
        createdAt: widget.existingRule?.createdAt,
      );

      if (_isEditing) {
        widget.ref.read(notificationProvider.notifier).updateRule(rule);
      } else {
        widget.ref.read(notificationProvider.notifier).addRule(rule);
      }

      Navigator.pop(context);
    }
  }
}
