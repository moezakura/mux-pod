import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
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
            const SizedBox(height: 24),
            const Text('Key Type'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'ed25519',
                  label: Text('Ed25519'),
                ),
                ButtonSegment(
                  value: 'rsa',
                  label: Text('RSA'),
                ),
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
              const Text('RSA Key Size'),
              Slider(
                value: _rsaBits.toDouble(),
                min: 2048,
                max: 4096,
                divisions: 2,
                label: '$_rsaBits bits',
                onChanged: (value) {
                  setState(() {
                    _rsaBits = value.toInt();
                  });
                },
              ),
              Center(child: Text('$_rsaBits bits')),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isGenerating ? null : _generate,
              child: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isGenerating = true;
    });

    try {
      // TODO: 鍵を生成
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key generated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate key: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }
}
