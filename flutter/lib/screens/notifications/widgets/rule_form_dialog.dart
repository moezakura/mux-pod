import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/enums.dart';
import '../../../models/notification_rule.dart';
import '../../../providers/notification_provider.dart';

/// ルール作成/編集ダイアログ
class RuleFormDialog extends ConsumerStatefulWidget {
  const RuleFormDialog({
    super.key,
    this.existingRule,
  });

  /// 既存ルール（編集モード時）
  final NotificationRule? existingRule;

  /// ダイアログを表示
  static Future<NotificationRule?> show(
    BuildContext context, {
    NotificationRule? existingRule,
  }) {
    return showModalBottomSheet<NotificationRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => RuleFormDialog(existingRule: existingRule),
    );
  }

  @override
  ConsumerState<RuleFormDialog> createState() => _RuleFormDialogState();
}

class _RuleFormDialogState extends ConsumerState<RuleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _patternController = TextEditingController();

  PatternType _patternType = PatternType.text;
  bool _caseSensitive = false;
  bool _negate = false;
  List<NotificationAction> _actions = [NotificationAction.inApp];
  NotificationFrequency _frequency = NotificationFrequency.always;
  RuleScope _scope = RuleScope.global;
  bool _enabled = true;

  bool get _isEditing => widget.existingRule != null;

  @override
  void initState() {
    super.initState();
    _initFromExistingRule();
  }

  void _initFromExistingRule() {
    final rule = widget.existingRule;
    if (rule == null) return;

    _nameController.text = rule.name;
    _descriptionController.text = rule.description ?? '';
    _actions = List.from(rule.actions);
    _frequency = rule.frequency;
    _scope = rule.scope;
    _enabled = rule.enabled;

    if (rule.conditions.isNotEmpty) {
      final condition = rule.conditions.first;
      _patternController.text = condition.pattern;
      _patternType = condition.patternType;
      _caseSensitive = condition.caseSensitive;
      _negate = condition.negate;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Form(
            key: _formKey,
            child: Column(
              children: [
                // ヘッダー
                _buildHeader(context),
                const Divider(height: 1),

                // フォーム本体
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ルール名
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Rule Name',
                          hintText: 'e.g., Error Detection',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a rule name';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // 説明（オプション）
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                          hintText: 'Describe what this rule does',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),

                      const SizedBox(height: 24),

                      // パターン設定セクション
                      _buildSectionHeader(context, 'Pattern'),

                      const SizedBox(height: 12),

                      // パターンタイプ
                      SegmentedButton<PatternType>(
                        segments: const [
                          ButtonSegment(
                            value: PatternType.text,
                            label: Text('Text'),
                            icon: Icon(Icons.text_fields),
                          ),
                          ButtonSegment(
                            value: PatternType.regex,
                            label: Text('Regex'),
                            icon: Icon(Icons.code),
                          ),
                          ButtonSegment(
                            value: PatternType.wildcard,
                            label: Text('Wildcard'),
                            icon: Icon(Icons.star),
                          ),
                        ],
                        selected: {_patternType},
                        onSelectionChanged: (selected) {
                          setState(() => _patternType = selected.first);
                        },
                      ),

                      const SizedBox(height: 12),

                      // パターン入力
                      TextFormField(
                        controller: _patternController,
                        decoration: InputDecoration(
                          labelText: 'Pattern',
                          hintText: _getPatternHint(),
                          border: const OutlineInputBorder(),
                          suffixIcon: _buildPatternValidationIcon(),
                        ),
                        style: const TextStyle(fontFamily: 'monospace'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a pattern';
                          }
                          if (!_validatePattern(value)) {
                            return 'Invalid pattern';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      // パターンオプション
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Case Sensitive'),
                              value: _caseSensitive,
                              onChanged: (value) {
                                setState(() => _caseSensitive = value ?? false);
                              },
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('Negate'),
                              value: _negate,
                              onChanged: (value) {
                                setState(() => _negate = value ?? false);
                              },
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // アクション設定セクション
                      _buildSectionHeader(context, 'Actions'),

                      const SizedBox(height: 12),

                      // アクション選択
                      Wrap(
                        spacing: 8,
                        children: NotificationAction.values.map((action) {
                          final selected = _actions.contains(action);
                          return FilterChip(
                            label: Text(_getActionLabel(action)),
                            avatar: Icon(_getActionIcon(action), size: 18),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  _actions.add(action);
                                } else {
                                  _actions.remove(action);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // 頻度設定セクション
                      _buildSectionHeader(context, 'Frequency'),

                      const SizedBox(height: 12),

                      // 頻度選択
                      ...NotificationFrequency.values.map((freq) {
                        return RadioListTile<NotificationFrequency>(
                          title: Text(_getFrequencyLabel(freq)),
                          subtitle: Text(_getFrequencyDescription(freq)),
                          value: freq,
                          groupValue: _frequency,
                          onChanged: (value) {
                            setState(() => _frequency = value!);
                          },
                          dense: true,
                        );
                      }),

                      const SizedBox(height: 24),

                      // スコープ設定セクション
                      _buildSectionHeader(context, 'Scope'),

                      const SizedBox(height: 12),

                      // スコープ選択
                      SegmentedButton<RuleScope>(
                        segments: const [
                          ButtonSegment(
                            value: RuleScope.global,
                            label: Text('Global'),
                            icon: Icon(Icons.public),
                          ),
                          ButtonSegment(
                            value: RuleScope.connection,
                            label: Text('Connection'),
                            icon: Icon(Icons.link),
                          ),
                          ButtonSegment(
                            value: RuleScope.session,
                            label: Text('Session'),
                            icon: Icon(Icons.terminal),
                          ),
                        ],
                        selected: {_scope},
                        onSelectionChanged: (selected) {
                          setState(() => _scope = selected.first);
                        },
                      ),

                      const SizedBox(height: 24),

                      // 有効/無効
                      SwitchListTile(
                        title: const Text('Enabled'),
                        subtitle: const Text('Turn this rule on or off'),
                        value: _enabled,
                        onChanged: (value) {
                          setState(() => _enabled = value);
                        },
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),

                // フッター
                _buildFooter(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isEditing ? 'Edit Rule' : 'New Rule',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FilledButton(
              onPressed: _saveRule,
              child: Text(_isEditing ? 'Save' : 'Create'),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildPatternValidationIcon() {
    final pattern = _patternController.text;
    if (pattern.isEmpty) return null;

    final isValid = _validatePattern(pattern);
    return Icon(
      isValid ? Icons.check_circle : Icons.error,
      color: isValid ? Colors.green : Colors.red,
    );
  }

  String _getPatternHint() {
    switch (_patternType) {
      case PatternType.text:
        return 'e.g., error, BUILD SUCCESS';
      case PatternType.regex:
        return r'e.g., ERROR:\s+\d+, \[WARN\].*';
      case PatternType.wildcard:
        return 'e.g., *error*, BUILD *';
    }
  }

  bool _validatePattern(String pattern) {
    final matcher = ref.read(patternMatcherProvider);
    return matcher.validatePattern(pattern, _patternType);
  }

  String _getActionLabel(NotificationAction action) {
    switch (action) {
      case NotificationAction.inApp:
        return 'In-app';
      case NotificationAction.sound:
        return 'Sound';
      case NotificationAction.vibrate:
        return 'Vibrate';
    }
  }

  IconData _getActionIcon(NotificationAction action) {
    switch (action) {
      case NotificationAction.inApp:
        return Icons.notifications;
      case NotificationAction.sound:
        return Icons.volume_up;
      case NotificationAction.vibrate:
        return Icons.vibration;
    }
  }

  String _getFrequencyLabel(NotificationFrequency freq) {
    switch (freq) {
      case NotificationFrequency.always:
        return 'Always';
      case NotificationFrequency.oncePerSession:
        return 'Once per session';
      case NotificationFrequency.oncePerMatch:
        return 'Once per match';
    }
  }

  String _getFrequencyDescription(NotificationFrequency freq) {
    switch (freq) {
      case NotificationFrequency.always:
        return 'Notify every time the pattern matches';
      case NotificationFrequency.oncePerSession:
        return 'Notify only once per connection session';
      case NotificationFrequency.oncePerMatch:
        return 'Notify only once for each unique match';
    }
  }

  Future<void> _saveRule() async {
    if (!_formKey.currentState!.validate()) return;

    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one action')),
      );
      return;
    }

    final condition = NotificationCondition(
      pattern: _patternController.text.trim(),
      patternType: _patternType,
      caseSensitive: _caseSensitive,
      negate: _negate,
    );

    final notifier = ref.read(notificationRulesProvider.notifier);

    NotificationRule result;

    if (_isEditing) {
      result = widget.existingRule!.copyWith(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        conditions: [condition],
        actions: _actions,
        frequency: _frequency,
        scope: _scope,
        enabled: _enabled,
        updatedAt: DateTime.now(),
      );
      await notifier.updateRule(result);
    } else {
      result = await notifier.create(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        conditions: [condition],
        actions: _actions,
        frequency: _frequency,
        scope: _scope,
      );
    }

    if (mounted) {
      Navigator.pop(context, result);
    }
  }
}
