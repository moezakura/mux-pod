import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/key_provider.dart';
import '../../theme/design_colors.dart';
import '../home_screen.dart';
import 'key_generate_screen.dart';
import 'key_import_screen.dart';
import 'widgets/key_tile.dart';

/// SSH鍵一覧画面
class KeysScreen extends ConsumerWidget {
  const KeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keysState = ref.watch(keysProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, ref),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: _buildBody(context, ref, keysState),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_add_ssh_key',
        onPressed: () {
          _showAddKeyOptions(context);
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add Key'),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 100,
      backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
        title: Text(
          'Keys',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.settings,
            color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
          ),
          onPressed: () => ref.read(currentTabProvider.notifier).setTab(3),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, KeysState state) {
    // ローディング中
    if (state.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // エラー
    if (state.error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('Error: ${state.error}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.read(keysProvider.notifier).reload();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 空状態
    if (state.keys.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? DesignColors.borderDark : DesignColors.borderLight,
                  ),
                ),
                child: Icon(
                  Icons.vpn_key_off,
                  size: 64,
                  color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No SSH keys yet',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? DesignColors.textSecondary : DesignColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the button below to add a key',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 鍵一覧
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final keyMeta = state.keys[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KeyTile(
              keyMeta: keyMeta,
              onCopyPublicKey: () {
                _copyPublicKey(context, keyMeta);
              },
              onDelete: () {
                _showDeleteConfirmation(context, ref, keyMeta);
              },
            ),
          );
        },
        childCount: state.keys.length,
      ),
    );
  }

  void _copyPublicKey(BuildContext context, SshKeyMeta keyMeta) {
    if (keyMeta.publicKey != null) {
      Clipboard.setData(ClipboardData(text: keyMeta.publicKey!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public key copied to clipboard')),
      );
    }
  }

  void _showDeleteConfirmation(
      BuildContext context, WidgetRef ref, SshKeyMeta keyMeta) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Key?'),
        content: Text(
          'Are you sure you want to delete "${keyMeta.name}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteKey(context, ref, keyMeta);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteKey(
      BuildContext context, WidgetRef ref, SshKeyMeta keyMeta) async {
    try {
      final storage = ref.read(secureStorageProvider);
      final keysNotifier = ref.read(keysProvider.notifier);

      // SecureStorageから秘密鍵を削除
      await storage.deletePrivateKey(keyMeta.id);

      // パスフレーズがあれば削除
      if (keyMeta.hasPassphrase) {
        await storage.deletePassphrase(keyMeta.id);
      }

      // メタデータを削除
      await keysNotifier.remove(keyMeta.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Key "${keyMeta.name}" deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete key: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const KeyGenerateScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Import Key'),
              subtitle: const Text('Import an existing private key'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const KeyImportScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
