import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              label: Text(_selectedFilePath ?? 'Select Private Key File'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Or paste the private key below:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _privateKeyController,
              decoration: const InputDecoration(
                labelText: 'Private Key (PEM format)',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                alignLabelWithHint: true,
              ),
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              validator: (value) {
                if ((value == null || value.isEmpty) && _selectedFilePath == null) {
                  return 'Please select a file or paste the private key';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passphraseController,
              decoration: const InputDecoration(
                labelText: 'Passphrase (optional)',
                hintText: 'Leave empty if key is not encrypted',
              ),
              obscureText: true,
            ),
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

  Future<void> _pickFile() async {
    // TODO: ファイルピッカーで秘密鍵ファイルを選択
  }

  Future<void> _import() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isImporting = true;
    });

    try {
      // TODO: 鍵をインポート
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key imported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import key: $e')),
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
