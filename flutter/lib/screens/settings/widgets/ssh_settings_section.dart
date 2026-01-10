import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_settings.dart';
import '../../../providers/settings_provider.dart';

/// SSH設定セクション
class SshSettingsSection extends ConsumerWidget {
  const SshSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ssh = ref.watch(sshSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.lan, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'SSH',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Connection Timeout
          ListTile(
            title: const Text('Connection Timeout'),
            subtitle: Text('${ssh.connectionTimeout} seconds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTimeoutPicker(
              context,
              ref,
              'Connection Timeout',
              ssh.connectionTimeout,
              [10, 15, 30, 60, 120],
              (value) async {
                await notifier.updateSshSettings(
                  ssh.copyWith(connectionTimeout: value),
                );
              },
            ),
          ),

          // Keep Alive Interval
          ListTile(
            title: const Text('Keep Alive Interval'),
            subtitle: Text('${ssh.keepAliveInterval} seconds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTimeoutPicker(
              context,
              ref,
              'Keep Alive Interval',
              ssh.keepAliveInterval,
              [0, 30, 60, 120, 300],
              (value) async {
                await notifier.updateSshSettings(
                  ssh.copyWith(keepAliveInterval: value),
                );
              },
              labels: {0: 'Disabled'},
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Reconnect Attempts
          ListTile(
            title: const Text('Reconnect Attempts'),
            subtitle: Text('${ssh.reconnectAttempts} attempts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showNumberPicker(
              context,
              ref,
              'Reconnect Attempts',
              ssh.reconnectAttempts,
              [0, 1, 3, 5, 10],
              (value) async {
                await notifier.updateSshSettings(
                  ssh.copyWith(reconnectAttempts: value),
                );
              },
              labels: {0: 'Disabled'},
            ),
          ),

          // Reconnect Delay
          ListTile(
            title: const Text('Reconnect Delay'),
            subtitle: Text('${ssh.reconnectDelay} seconds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTimeoutPicker(
              context,
              ref,
              'Reconnect Delay',
              ssh.reconnectDelay,
              [1, 3, 5, 10, 30],
              (value) async {
                await notifier.updateSshSettings(
                  ssh.copyWith(reconnectDelay: value),
                );
              },
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Compression
          SwitchListTile(
            title: const Text('Compression'),
            subtitle: const Text('Enable SSH data compression'),
            value: ssh.compression,
            onChanged: (value) async {
              await notifier.updateSshSettings(
                ssh.copyWith(compression: value),
              );
            },
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Default PTY Size
          ListTile(
            title: const Text('Default PTY Size'),
            subtitle: Text('${ssh.defaultPtyWidth} x ${ssh.defaultPtyHeight}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPtySizePicker(context, ref, ssh),
          ),

          // Default TERM
          ListTile(
            title: const Text('Default TERM'),
            subtitle: Text(ssh.defaultTerm),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTermPicker(context, ref, ssh.defaultTerm),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showTimeoutPicker(
    BuildContext context,
    WidgetRef ref,
    String title,
    int current,
    List<int> options,
    Future<void> Function(int) onSelect, {
    Map<int, String>? labels,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((value) {
              final label = labels?[value] ?? '$value seconds';
              return ListTile(
                title: Text(label),
                trailing: value == current
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await onSelect(value);
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showNumberPicker(
    BuildContext context,
    WidgetRef ref,
    String title,
    int current,
    List<int> options,
    Future<void> Function(int) onSelect, {
    Map<int, String>? labels,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((value) {
              final label = labels?[value] ?? '$value';
              return ListTile(
                title: Text(label),
                trailing: value == current
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await onSelect(value);
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showPtySizePicker(BuildContext context, WidgetRef ref, SshSettings ssh) {
    final options = [
      (80, 24, '80 x 24 (Standard)'),
      (120, 40, '120 x 40 (Large)'),
      (160, 50, '160 x 50 (Wide)'),
      (200, 60, '200 x 60 (Extra Large)'),
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Default PTY Size',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((opt) {
              final (width, height, label) = opt;
              final isCurrent = ssh.defaultPtyWidth == width && ssh.defaultPtyHeight == height;
              return ListTile(
                title: Text(label),
                trailing: isCurrent
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref.read(appSettingsProvider.notifier).updateSshSettings(
                        ssh.copyWith(defaultPtyWidth: width, defaultPtyHeight: height),
                      );
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showTermPicker(BuildContext context, WidgetRef ref, String current) {
    final options = [
      'xterm-256color',
      'xterm',
      'vt100',
      'screen',
      'screen-256color',
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Default TERM',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((term) {
              return ListTile(
                title: Text(term),
                trailing: term == current
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  final ssh = ref.read(sshSettingsProvider);
                  await ref.read(appSettingsProvider.notifier).updateSshSettings(
                        ssh.copyWith(defaultTerm: term),
                      );
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
