import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/l10n_ext.dart';
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
      appBar: AppBar(title: Text(context.l10n.keyMgmtImportTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: context.l10n.keyMgmtKeyName,
                hintText: context.l10n.keyMgmtKeyNameHint,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.l10n.keyMgmtNameRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_upload),
              label: Text(
                _selectedFilePath != null
                    ? _selectedFilePath!.split('/').last
                    : context.l10n.keyMgmtSelectFile,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.keyMgmtOrPaste,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _privateKeyController,
              decoration: InputDecoration(
                labelText: context.l10n.keyMgmtPemLabel,
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
                  return context.l10n.keyMgmtKeyRequired;
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
                      ? context.l10n.keyMgmtPassphraseRequired
                      : context.l10n.keyMgmtPassphraseOptional,
                  hintText: _isEncrypted
                      ? context.l10n.keyMgmtPassphraseDecryptHint
                      : context.l10n.keyMgmtPassphraseEmptyHint,
                ),
                obscureText: true,
                validator: (value) {
                  if (_isEncrypted && (value == null || value.isEmpty)) {
                    return context.l10n.keyMgmtPassphraseRequiredError;
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
                child: Text(context.l10n.keyMgmtAddPassphrase),
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
                  : Text(context.l10n.keyMgmtImport),
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
        _pemValidationError = context.l10n.keyMgmtInvalidPem;
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
        _pemValidationError = context.l10n.keyMgmtInvalidPem;
        _isEncrypted = false;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);

      if (file != null) {
        // ファイル内容を読み取る
        String content;
        try {
          final bytes = await file.readAsBytes();
          content = String.fromCharCodes(bytes);
        } catch (_) {
          // 読み取りに失敗した
          if (mounted) {
            setState(() {
              _pemValidationError = context.l10n.keyMgmtCouldNotReadFile;
            });
          }
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
            content: Text(context.l10n.keyMgmtPickFileFailed('$e')),
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
        l10n: context.l10n,
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
          SnackBar(content: Text(context.l10n.keyMgmtImportedSuccess(name))),
        );
      }
    } on FormatException catch (e) {
      // 無効なPEM形式またはパスフレーズエラー
      if (mounted) {
        final message = e.message.contains('passphrase')
            ? context.l10n.keyMgmtWrongPassphrase
            : context.l10n.keyMgmtInvalidKeyFormat(e.message);
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
            content: Text(context.l10n.keyMgmtImportFailed('$e')),
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
