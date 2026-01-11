import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../providers/key_provider.dart';

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
  bool _isImporting = false;
  String? _selectedFilePath;
  String? _pemValidationError;
  bool _isEncrypted = false;
  bool _showPassphrase = false;

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
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Key Name',
                hintText: 'My SSH Key',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_upload),
              label: Text(_selectedFilePath != null
                  ? _selectedFilePath!.split('/').last
                  : 'Select Private Key File'),
            ),
            const SizedBox(height: 8),
            Text(
              'Or paste the private key below:',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _privateKeyController,
              decoration: InputDecoration(
                labelText: 'Private Key (PEM format)',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                alignLabelWithHint: true,
                errorText: _pemValidationError,
              ),
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              onChanged: _onPemChanged,
              validator: (value) {
                if ((value == null || value.isEmpty) &&
                    _selectedFilePath == null) {
                  return 'Please select a file or paste the private key';
                }
                if (_pemValidationError != null) {
                  return _pemValidationError;
                }
                return null;
              },
            ),
            if (_isEncrypted || _showPassphrase) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _passphraseController,
                decoration: InputDecoration(
                  labelText: _isEncrypted
                      ? 'Passphrase (required - key is encrypted)'
                      : 'Passphrase (optional)',
                  hintText: _isEncrypted
                      ? 'Enter passphrase to decrypt'
                      : 'Leave empty if key is not encrypted',
                ),
                obscureText: true,
                validator: (value) {
                  if (_isEncrypted && (value == null || value.isEmpty)) {
                    return 'Passphrase is required for encrypted keys';
                  }
                  return null;
                },
              ),
            ],
            if (!_isEncrypted && !_showPassphrase) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _showPassphrase = true;
                  });
                },
                child: const Text('Add passphrase (if key is encrypted)'),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isImporting ? null : _import,
              child: _isImporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  void _onPemChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _pemValidationError = null;
        _isEncrypted = false;
      });
      return;
    }

    final keyService = ref.read(sshKeyServiceProvider);

    // PEM形式の基本的なバリデーション
    if (!value.contains('-----BEGIN') || !value.contains('-----END')) {
      setState(() {
        _pemValidationError = 'Invalid PEM format';
        _isEncrypted = false;
      });
      return;
    }

    try {
      // 暗号化されているかチェック
      final isEncrypted = keyService.isEncrypted(value);
      setState(() {
        _pemValidationError = null;
        _isEncrypted = isEncrypted;
        if (isEncrypted) {
          _showPassphrase = true;
        }
      });
    } catch (e) {
      setState(() {
        _pemValidationError = 'Invalid PEM format';
        _isEncrypted = false;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // ファイル内容を読み取る
        String content;
        if (file.bytes != null) {
          content = String.fromCharCodes(file.bytes!);
        } else {
          // ファイルパスから読み取る（デスクトップ向け）
          setState(() {
            _pemValidationError = 'Could not read file content';
          });
          return;
        }

        setState(() {
          _selectedFilePath = file.path ?? file.name;
          _privateKeyController.text = content;
        });

        // PEMの検証
        _onPemChanged(content);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _import() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final keyService = ref.read(sshKeyServiceProvider);
      final storage = ref.read(secureStorageProvider);
      final keysNotifier = ref.read(keysProvider.notifier);

      final pemContent = _privateKeyController.text.trim();
      final passphrase = _passphraseController.text.isNotEmpty
          ? _passphraseController.text
          : null;
      final name = _nameController.text.trim();
      final keyId = const Uuid().v4();

      // PEMをパース
      final keyPair = await keyService.parseFromPem(
        pemContent,
        passphrase: passphrase,
      );

      // 秘密鍵をSecureStorageに保存
      await storage.savePrivateKey(keyId, pemContent);

      // パスフレーズがあれば保存
      if (passphrase != null) {
        await storage.savePassphrase(keyId, passphrase);
      }

      // メタデータをKeysNotifierに保存
      final meta = SshKeyMeta(
        id: keyId,
        name: name,
        type: keyPair.type,
        publicKey: keyPair.publicKeyString,
        fingerprint: keyPair.fingerprint,
        hasPassphrase: passphrase != null || _isEncrypted,
        createdAt: DateTime.now(),
        comment: name,
        source: KeySource.imported,
      );
      await keysNotifier.add(meta);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Key "$name" imported successfully')),
        );
      }
    } on FormatException catch (e) {
      // 無効なPEM形式またはパスフレーズエラー
      if (mounted) {
        final message = e.message.contains('passphrase')
            ? 'Wrong passphrase. Please check and try again.'
            : 'Invalid key format: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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
        setState(() {
          _isImporting = false;
        });
      }
    }
  }
}
