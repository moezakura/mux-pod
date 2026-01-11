import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SSH鍵一覧画面
class KeysScreen extends ConsumerWidget {
  const KeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Keys'),
      ),
      body: const Center(
        child: Text('No SSH keys yet'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddKeyOptions(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddKeyOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle),
              title: const Text('Generate New Key'),
              subtitle: const Text('Create a new RSA or Ed25519 key'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 鍵生成画面へ遷移
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Import Key'),
              subtitle: const Text('Import an existing private key'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 鍵インポート画面へ遷移
              },
            ),
          ],
        ),
      ),
    );
  }
}
