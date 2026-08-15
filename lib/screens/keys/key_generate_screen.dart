import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/key_provider.dart';
import '../../services/keychain/ssh_key_service.dart';

/// SSH鍵生成画面
class KeyGenerateScreen extends ConsumerStatefulWidget {
  const KeyGenerateScreen({super.key});

  @override
  ConsumerState<KeyGenerateScreen> createState() => _KeyGenerateScreenState();
}

class _KeyGenerateScreenState extends ConsumerState<KeyGenerateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _keyType = 'ed25519';
  int _rsaBits = 4096;
  bool _isGenerating = false;
  String? _statusMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.keyMgmtGenerateTitle)),
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
            const SizedBox(height: 24),
            Text(context.l10n.keyMgmtKeyType),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ed25519', label: Text('Ed25519')),
                ButtonSegment(value: 'rsa', label: Text('RSA')),
              ],
              selected: {_keyType},
              onSelectionChanged: (selected) {
                setState(() {
                  _keyType = selected.first;
                });
              },
            ),
            if (_keyType == 'rsa') ...[
              const SizedBox(height: 16),
              Text(context.l10n.keyMgmtRsaKeySize),
              Slider(
                value: _rsaBits.toDouble(),
                min: 2048,
                max: 4096,
                divisions: 2,
                label: context.l10n.keyMgmtBits(_rsaBits),
                onChanged: (value) {
                  setState(() {
                    _rsaBits = value.toInt();
                  });
                },
              ),
              Center(child: Text(context.l10n.keyMgmtBits(_rsaBits))),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isGenerating ? null : _generate,
              child: _isGenerating
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        if (_statusMessage != null) ...[
                          const SizedBox(width: 12),
                          Text(_statusMessage!),
                        ],
                      ],
                    )
                  : Text(context.l10n.keyMgmtGenerate),
            ),
            if (_keyType == 'rsa') ...[
              const SizedBox(height: 8),
              Text(
                'RSA key generation may take a few seconds',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isGenerating = true;
      _statusMessage = context.l10n.keyMgmtGenerating;
    });

    try {
      final keyService = ref.read(sshKeyServiceProvider);
      final storage = ref.read(secureStorageProvider);
      final keysNotifier = ref.read(keysProvider.notifier);

      final keyId = const Uuid().v4();
      final name = _nameController.text.trim();

      // 鍵を生成
      SshKeyPair keyPair;
      if (_keyType == 'ed25519') {
        keyPair = await keyService.generateEd25519(comment: name);
      } else {
        // RSA生成は時間がかかる（UIをブロックするが許容範囲）
        setState(() {
          _statusMessage = context.l10n.keyMgmtGeneratingRsa;
        });
        // 一瞬UIを更新させるためにmicrotaskで実行
        await Future.delayed(const Duration(milliseconds: 50));
        keyPair = await keyService.generateRsa(bits: _rsaBits, comment: name);
      }

      setState(() {
        _statusMessage = context.l10n.keyMgmtSaving;
      });

      // 秘密鍵をSecureStorageに保存
      await storage.savePrivateKey(keyId, keyPair.privatePem);

      // メタデータをKeysNotifierに保存
      final meta = SshKeyMeta(
        id: keyId,
        name: name,
        type: keyPair.type,
        publicKey: keyPair.publicKeyString,
        fingerprint: keyPair.fingerprint,
        hasPassphrase: false,
        createdAt: DateTime.now(),
        comment: name,
        source: KeySource.generated,
      );
      await keysNotifier.add(meta);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.keyMgmtGeneratedSuccess(name))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.keyMgmtGenerateFailed('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _statusMessage = null;
        });
      }
    }
  }
}
