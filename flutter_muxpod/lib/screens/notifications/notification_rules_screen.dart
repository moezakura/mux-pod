import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通知ルール一覧画面
class NotificationRulesScreen extends ConsumerWidget {
  const NotificationRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Rules'),
      ),
      body: const Center(
        child: Text('No notification rules yet'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddRuleDialog(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _RuleFormDialog(),
    );
  }
}

class _RuleFormDialog extends StatefulWidget {
  final String? ruleId;

  const _RuleFormDialog({this.ruleId});

  @override
  State<_RuleFormDialog> createState() => _RuleFormDialogState();
}

class _RuleFormDialogState extends State<_RuleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _patternController = TextEditingController();
  bool _isRegex = false;
  bool _vibrate = true;

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.ruleId != null ? 'Edit Rule' : 'New Rule'),
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
      // TODO: ルールを保存
      Navigator.pop(context);
    }
  }
}
