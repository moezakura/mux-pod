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
class KeysScreen extends ConsumerStatefulWidget {
  const KeysScreen({super.key});

  @override
  ConsumerState<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends ConsumerState<KeysScreen> {
  /// 破損鍵モーダルを表示済みか（同一セッション内で一度だけ表示する）
  bool _damagedKeysDialogShown = false;

  @override
  Widget build(BuildContext context) {
    final keysState = ref.watch(keysProvider);

    // 破損鍵が検出された場合、起動時に一度だけモーダルを表示する
    ref.listen(keysProvider, (prev, next) {
      if (!_damagedKeysDialogShown && next.damagedKeys.isNotEmpty) {
        _damagedKeysDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showDamagedKeysDialog(next.damagedKeys);
        });
      }
    });

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
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_add_ssh_key',
        onPressed: () => _showAddKeyOptions(context),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.add),
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
            color: isDark
                ? DesignColors.textSecondary
                : DesignColors.textSecondaryLight,
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
                  color: isDark
                      ? DesignColors.surfaceDark
                      : DesignColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? DesignColors.borderDark
                        : DesignColors.borderLight,
                  ),
                ),
                child: Icon(
                  Icons.vpn_key_off,
                  size: 64,
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No SSH keys yet',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the button below to add a key',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 鍵一覧
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
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
      }, childCount: state.keys.length),
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
    BuildContext context,
    WidgetRef ref,
    SshKeyMeta keyMeta,
  ) {
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
    BuildContext context,
    WidgetRef ref,
    SshKeyMeta keyMeta,
  ) async {
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

  /// 破損鍵検出モーダル（削除 or 保持を選択）
  Future<void> _showDamagedKeysDialog(List<SshKeyMeta> damagedKeys) async {
    if (!mounted) return;
    final selected = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('破損した鍵が見つかりました'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('秘密鍵を読み出せない鍵があります。削除するか、そのまま残すかを選択してください。'),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: damagedKeys.map((key) {
                          return CheckboxListTile(
                            dense: true,
                            title: Text(key.name),
                            subtitle: Text(
                              '${key.type} · ${_shortFingerprint(key.fingerprint)}',
                            ),
                            value: selected.contains(key.id),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selected.add(key.id);
                                } else {
                                  selected.remove(key.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('そのままにする'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () async {
                          await _deleteDamagedKeys(selected.toList());
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                  child: const Text('選択した鍵を削除'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 選択された破損鍵（メタデータ + 秘密鍵）を削除する
  Future<void> _deleteDamagedKeys(List<String> keyIds) async {
    final storage = ref.read(secureStorageProvider);
    final keysNotifier = ref.read(keysProvider.notifier);
    try {
      for (final id in keyIds) {
        await storage.deletePrivateKey(id);
        await storage.deletePassphrase(id);
        await keysNotifier.remove(id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete key: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// フィンガープリントの先頭を短縮表示する
  String _shortFingerprint(String? fingerprint) {
    if (fingerprint == null) return '';
    return fingerprint.length > 12 ? fingerprint.substring(0, 12) : fingerprint;
  }
}
