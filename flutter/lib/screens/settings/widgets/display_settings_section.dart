import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart';

/// 表示設定セクション
class DisplaySettingsSection extends ConsumerWidget {
  const DisplaySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(displaySettingsProvider);
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
                Icon(Icons.display_settings, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Display',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Use System Theme
          SwitchListTile(
            title: const Text('Use System Theme'),
            subtitle: const Text('Follow device light/dark mode'),
            value: display.useSystemTheme,
            onChanged: (value) async {
              await notifier.updateDisplaySettings(
                display.copyWith(useSystemTheme: value),
              );
            },
          ),

          // Dark Mode (disabled if system theme is on)
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Use dark color scheme'),
            value: display.darkMode,
            onChanged: display.useSystemTheme
                ? null
                : (value) async {
                    await notifier.setDarkMode(value);
                  },
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Keep Screen On
          SwitchListTile(
            title: const Text('Keep Screen On'),
            subtitle: const Text('Prevent screen from sleeping'),
            value: display.keepScreenOn,
            onChanged: (value) async {
              await notifier.setKeepScreenOn(value);
            },
          ),

          // Lock Orientation
          SwitchListTile(
            title: const Text('Lock Orientation'),
            subtitle: const Text('Prevent screen rotation'),
            value: display.lockOrientation,
            onChanged: (value) async {
              await notifier.updateDisplaySettings(
                display.copyWith(lockOrientation: value),
              );
            },
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Full Screen Mode
          SwitchListTile(
            title: const Text('Full Screen Mode'),
            subtitle: const Text('Hide system navigation'),
            value: display.fullScreen,
            onChanged: (value) async {
              await notifier.updateDisplaySettings(
                display.copyWith(fullScreen: value),
              );
            },
          ),

          // Show Status Bar
          SwitchListTile(
            title: const Text('Show Status Bar'),
            subtitle: const Text('Display system status bar'),
            value: display.showStatusBar,
            onChanged: (value) async {
              await notifier.updateDisplaySettings(
                display.copyWith(showStatusBar: value),
              );
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
