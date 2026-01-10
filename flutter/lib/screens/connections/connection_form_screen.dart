import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_method.dart';
import '../../models/ssh_key.dart';
import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../router/app_router.dart';

/// 接続フォーム画面
class ConnectionFormScreen extends ConsumerStatefulWidget {
  const ConnectionFormScreen({
    super.key,
    this.connectionId,
  });

  final String? connectionId;

  bool get isEditing => connectionId != null;

  @override
  ConsumerState<ConnectionFormScreen> createState() => _ConnectionFormScreenState();
}

class _ConnectionFormScreenState extends ConsumerState<ConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _tagsController;

  bool _usePassword = true;
  String? _selectedKeyId;
  SSHKey? _selectedKey;
  bool _showPassword = false;
  bool _isLoading = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _hostController = TextEditingController();
    _portController = TextEditingController(text: '22');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _tagsController = TextEditingController();

    if (widget.isEditing) {
      _loadConnection();
    }
  }

  Future<void> _loadConnection() async {
    setState(() => _isLoading = true);

    try {
      final connection = await ref.read(connectionProvider(widget.connectionId!).future);
      if (connection != null && mounted) {
        _nameController.text = connection.name;
        _hostController.text = connection.host;
        _portController.text = connection.port.toString();
        _usernameController.text = connection.username;
        _tagsController.text = connection.tags.join(', ');

        connection.authMethod.when(
          password: () {
            setState(() => _usePassword = true);
          },
          key: (keyId) async {
            final key = await ref.read(keyProvider(keyId).future);
            if (mounted) {
              setState(() {
                _usePassword = false;
                _selectedKeyId = keyId;
                _selectedKey = key;
              });
            }
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Connection' : 'New Connection'),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
              tooltip: 'Delete',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 接続名
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Connection Name',
                      hintText: 'My Server',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ホスト名
                  TextFormField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Host',
                      hintText: 'example.com or 192.168.1.1',
                      prefixIcon: Icon(Icons.computer),
                    ),
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a host';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ポート番号
                  TextFormField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '22',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a port';
                      }
                      final port = int.tryParse(value);
                      if (port == null || port < 1 || port > 65535) {
                        return 'Port must be 1-65535';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ユーザー名
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'root',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a username';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // 認証方法セレクター
                  Text(
                    'Authentication',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Password'),
                        icon: Icon(Icons.password),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('SSH Key'),
                        icon: Icon(Icons.key),
                      ),
                    ],
                    selected: {_usePassword},
                    onSelectionChanged: (selected) {
                      setState(() => _usePassword = selected.first);
                    },
                  ),
                  const SizedBox(height: 16),

                  // パスワード入力（パスワード認証の場合）
                  if (_usePassword)
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: widget.isEditing ? 'Password (leave empty to keep)' : 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      obscureText: !_showPassword,
                      validator: (value) {
                        if (!widget.isEditing && (value == null || value.isEmpty)) {
                          return 'Please enter a password';
                        }
                        return null;
                      },
                    ),

                  // SSH鍵選択（鍵認証の場合）
                  if (!_usePassword) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedKey != null) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.key,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedKey!.name,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_selectedKey!.type.name.toUpperCase()} - ${_selectedKey!.fingerprint}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                fontFamily: 'monospace',
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _selectedKey = null;
                                        _selectedKeyId = null;
                                      });
                                    },
                                    icon: const Icon(Icons.close),
                                    tooltip: 'Clear selection',
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.key_off,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'No key selected',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _selectKey,
                                    icon: const Icon(Icons.list),
                                    label: const Text('Select Key'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => context.push(AppRoutes.keyGenerate),
                                  icon: const Icon(Icons.add),
                                  label: const Text('New'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!widget.isEditing && _selectedKeyId == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 12),
                        child: Text(
                          'Please select an SSH key',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],

                  const SizedBox(height: 24),

                  // タグ
                  TextFormField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags (optional)',
                      hintText: 'production, web, database',
                      prefixIcon: Icon(Icons.tag),
                      helperText: 'Separate tags with commas',
                    ),
                    textInputAction: TextInputAction.done,
                  ),

                  const SizedBox(height: 32),

                  // アクションボタン
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isTesting ? null : _testConnection,
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_find),
                          label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  void _selectKey() {
    showModalBottomSheet<SSHKey>(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Consumer(
              builder: (context, ref, _) {
                final keysAsync = ref.watch(keysProvider);
                return Column(
                  children: [
                    // ハンドルバー
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // タイトル
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            'Select SSH Key',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(bottomSheetContext);
                              context.push(AppRoutes.keyGenerate);
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('New Key'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // 鍵リスト
                    Expanded(
                      child: keysAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                        data: (keys) {
                          if (keys.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.key_off,
                                    size: 48,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No SSH keys available',
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: () {
                                      Navigator.pop(bottomSheetContext);
                                      context.push(AppRoutes.keyGenerate);
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Generate Key'),
                                  ),
                                ],
                              ),
                            );
                          }
                          return ListView.builder(
                            controller: scrollController,
                            itemCount: keys.length,
                            itemBuilder: (context, index) {
                              final key = keys[index];
                              final isSelected = key.id == _selectedKeyId;
                              return ListTile(
                                leading: Icon(
                                  Icons.key,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                title: Text(
                                  key.name,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : null,
                                  ),
                                ),
                                subtitle: Text(
                                  '${key.type.name.toUpperCase()} - ${key.fingerprint}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: Theme.of(context).colorScheme.primary,
                                      )
                                    : (key.isDefault
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primaryContainer,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Default',
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          )
                                        : null),
                                onTap: () {
                                  Navigator.pop(bottomSheetContext, key);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).then((selectedKey) {
      if (selectedKey != null && mounted) {
        setState(() {
          _selectedKey = selectedKey;
          _selectedKeyId = selectedKey.id;
        });
      }
    });
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_usePassword && _selectedKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an SSH key')),
      );
      return;
    }

    setState(() => _isTesting = true);

    try {
      // TODO: 接続テストの実装
      await Future<void>.delayed(const Duration(seconds: 2));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_usePassword && _selectedKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an SSH key')),
      );
      return;
    }

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final authMethod = _usePassword
        ? const AuthMethod.password()
        : AuthMethod.key(keyId: _selectedKeyId!);

    final notifier = ref.read(connectionsProvider.notifier);

    try {
      if (widget.isEditing) {
        // 既存接続の更新
        final existing = await ref.read(connectionProvider(widget.connectionId!).future);
        if (existing != null) {
          await notifier.updateConnection(
            existing.copyWith(
              name: _nameController.text.trim(),
              host: _hostController.text.trim(),
              port: int.parse(_portController.text),
              username: _usernameController.text.trim(),
              authMethod: authMethod,
              keyId: _usePassword ? null : _selectedKeyId,
              tags: tags,
            ),
          );

          // パスワードが入力されていれば更新
          if (_usePassword && _passwordController.text.isNotEmpty) {
            await notifier.updatePassword(
              connectionId: widget.connectionId!,
              password: _passwordController.text,
            );
          }
        }
      } else {
        // 新規接続の追加
        await notifier.add(
          name: _nameController.text.trim(),
          host: _hostController.text.trim(),
          port: int.parse(_portController.text),
          username: _usernameController.text.trim(),
          authMethod: authMethod,
          password: _usePassword ? _passwordController.text : null,
          keyId: _usePassword ? null : _selectedKeyId,
          tags: tags,
        );
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing ? 'Connection updated' : 'Connection added'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _confirmDelete() {
    final stateContext = context;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Connection'),
          content: const Text('Are you sure you want to delete this connection?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await ref.read(connectionsProvider.notifier).delete(widget.connectionId!);
                if (!mounted) return;
                stateContext.pop();
                ScaffoldMessenger.of(stateContext).showSnackBar(
                  const SnackBar(content: Text('Connection deleted')),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
