import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/key_provider.dart';
import '../../services/keychain/key_import.dart';

/// SSH鍵インポート画面
class KeyImportScreen extends ConsumerStatefulWidget {
  const KeyImportScreen({super.key});

  @override
  ConsumerState<KeyImportScreen> createState() => _KeyImportScreenState();
}

class _KeyImportScreenState extends ConsumerState<KeyImportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  bool _showPassphrase = false;
  bool _isImporting = false;
  bool _needsPassphrase = false;
  String? _previewFingerprint;
  String? _previewType;

  @override
  void dispose() {
    _nameController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import SSH Key'),
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
                hintText: 'Imported Key',
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

            // インポート方法
            Text(
              'Private Key',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),

            // ファイルから選択ボタン
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_upload),
              label: const Text('Select Private Key File'),
            ),
            const SizedBox(height: 16),

            // または手動入力
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'or paste below',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            // 秘密鍵テキスト入力
            TextFormField(
              controller: _privateKeyController,
              decoration: const InputDecoration(
                labelText: 'Private Key (PEM format)',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              maxLines: 8,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              onChanged: (_) => _validateKey(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter or select a private key';
                }
                if (!value.contains('-----BEGIN') ||
                    !value.contains('-----END')) {
                  return 'Invalid PEM format';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // プレビュー情報
            if (_previewFingerprint != null || _previewType != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Key Detected',
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_previewType != null)
                        Text('Type: $_previewType',
                            style: Theme.of(context).textTheme.bodySmall),
                      if (_previewFingerprint != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Fingerprint: $_previewFingerprint',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // パスフレーズ要求メッセージ
            if (_needsPassphrase) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This key is encrypted. Please enter the passphrase.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // パスフレーズ入力
            TextFormField(
              controller: _passphraseController,
              decoration: InputDecoration(
                labelText: _needsPassphrase
                    ? 'Passphrase (required)'
                    : 'Passphrase (optional)',
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
                if (_needsPassphrase && (value == null || value.isEmpty)) {
                  return 'Passphrase is required for this key';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),

            // インポートボタン
            FilledButton.icon(
              onPressed: _isImporting ? null : _import,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download),
              label: Text(_isImporting ? 'Importing...' : 'Import Key'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        _privateKeyController.text = content;

        // 名前が空なら、ファイル名から設定
        if (_nameController.text.isEmpty) {
          final fileName = result.files.single.name;
          _nameController.text = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
        }

        _validateKey();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read file: $e')),
        );
      }
    }
  }

  Future<void> _validateKey() async {
    final content = _privateKeyController.text.trim();
    if (content.isEmpty) {
      setState(() {
        _needsPassphrase = false;
        _previewFingerprint = null;
        _previewType = null;
      });
      return;
    }

    // 暗号化されているかチェック
    final isEncrypted = content.contains('ENCRYPTED') ||
        content.contains('Proc-Type: 4,ENCRYPTED') ||
        content.contains('DEK-Info:');

    setState(() {
      _needsPassphrase = isEncrypted;
    });

    // パスなしでパースを試行
    if (!isEncrypted) {
      try {
        final importer = ref.read(keyImportServiceProvider);
        final result = await importer.parsePrivateKey(content);
        setState(() {
          _previewFingerprint = result.fingerprint;
          _previewType = result.type.name.toUpperCase();
          if (result.bits != null) {
            _previewType = '$_previewType ${result.bits} bits';
          }
        });
      } catch (e) {
        setState(() {
          _previewFingerprint = null;
          _previewType = null;
        });
      }
    }
  }

  Future<void> _import() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isImporting = true);

    try {
      final notifier = ref.read(keysProvider.notifier);
      await notifier.import(
        name: _nameController.text.trim(),
        privateKeyPem: _privateKeyController.text.trim(),
        passphrase:
            _passphraseController.text.isEmpty ? null : _passphraseController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Key imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } on KeyImportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import key: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }
}
