import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../providers/key_provider.dart';

/// SSH鍵生成画面
class KeyGenerateScreen extends ConsumerStatefulWidget {
  const KeyGenerateScreen({super.key});

  @override
  ConsumerState<KeyGenerateScreen> createState() => _KeyGenerateScreenState();
}

class _KeyGenerateScreenState extends ConsumerState<KeyGenerateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _commentController = TextEditingController();

  KeyType _keyType = KeyType.ed25519;
  int _rsaBits = 4096;
  bool _usePassphrase = false;
  bool _showPassphrase = false;
  bool _isGenerating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _passphraseController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate SSH Key'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 鍵名
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Key Name',
                hintText: 'My Server Key',
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
            const SizedBox(height: 24),

            // 鍵タイプ選択
            Text(
              'Key Type',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<KeyType>(
              segments: const [
                ButtonSegment(
                  value: KeyType.ed25519,
                  label: Text('Ed25519'),
                  icon: Icon(Icons.speed),
                ),
                ButtonSegment(
                  value: KeyType.rsa,
                  label: Text('RSA'),
                  icon: Icon(Icons.lock),
                ),
                ButtonSegment(
                  value: KeyType.ecdsa,
                  label: Text('ECDSA'),
                  icon: Icon(Icons.security),
                ),
              ],
              selected: {_keyType},
              onSelectionChanged: (selected) {
                setState(() => _keyType = selected.first);
              },
            ),
            const SizedBox(height: 8),
            _buildKeyTypeDescription(),
            const SizedBox(height: 16),

            // RSAビット数（RSAの場合のみ）
            if (_keyType == KeyType.rsa) ...[
              Text(
                'Key Size',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 2048,
                    label: Text('2048'),
                  ),
                  ButtonSegment(
                    value: 3072,
                    label: Text('3072'),
                  ),
                  ButtonSegment(
                    value: 4096,
                    label: Text('4096'),
                  ),
                ],
                selected: {_rsaBits},
                onSelectionChanged: (selected) {
                  setState(() => _rsaBits = selected.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                _rsaBits == 4096
                    ? 'Recommended for maximum security'
                    : _rsaBits == 3072
                        ? 'Good balance of security and performance'
                        : 'Minimum recommended size',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
            ],

            // パスフレーズ
            SwitchListTile(
              title: const Text('Protect with passphrase'),
              subtitle: const Text('Additional security for the private key'),
              value: _usePassphrase,
              onChanged: (value) {
                setState(() => _usePassphrase = value);
              },
            ),

            if (_usePassphrase) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _passphraseController,
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassphrase ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _showPassphrase = !_showPassphrase);
                    },
                  ),
                ),
                obscureText: !_showPassphrase,
                validator: (value) {
                  if (_usePassphrase && (value == null || value.isEmpty)) {
                    return 'Please enter a passphrase';
                  }
                  if (_usePassphrase && value != null && value.length < 8) {
                    return 'Passphrase must be at least 8 characters';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 16),

            // コメント
            TextFormField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                hintText: 'user@hostname',
                prefixIcon: Icon(Icons.comment_outlined),
                helperText: 'Will be appended to the public key',
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 32),

            // 生成ボタン
            FilledButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_circle_outline),
              label: Text(_isGenerating ? 'Generating...' : 'Generate Key'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyTypeDescription() {
    final description = switch (_keyType) {
      KeyType.ed25519 => 'Modern, fast, and secure. Recommended for most uses.',
      KeyType.rsa =>
        'Widely compatible. Use 4096 bits for long-term security.',
      KeyType.ecdsa => 'Elliptic curve cryptography. Good security with smaller keys.',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final notifier = ref.read(keysProvider.notifier);
      final sshKey = await notifier.generate(
        name: _nameController.text.trim(),
        type: _keyType,
        bits: _keyType == KeyType.rsa ? _rsaBits : null,
        passphrase: _usePassphrase ? _passphraseController.text : null,
        comment: _commentController.text.trim(),
      );

      if (mounted) {
        // 公開鍵をクリップボードにコピー
        await Clipboard.setData(ClipboardData(text: sshKey.publicKey));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key generated! Public key copied to clipboard.'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate key: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }
}
