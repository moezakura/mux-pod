import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/settings_provider.dart';
import '../../widgets/dialogs/font_size_dialog.dart';
import '../../widgets/dialogs/font_family_dialog.dart';
import '../../widgets/dialogs/theme_dialog.dart';
import '../notifications/notification_rules_screen.dart';

/// 設定画面
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Terminal'),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Font Size'),
            subtitle: Text('${settings.fontSize.toInt()}'),
            onTap: () async {
              final size = await showDialog<double>(
                context: context,
                builder: (context) => FontSizeDialog(
                  currentSize: settings.fontSize,
                ),
              );
              if (size != null) {
                ref.read(settingsProvider.notifier).setFontSize(size);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.font_download),
            title: const Text('Font Family'),
            subtitle: Text(settings.fontFamily),
            onTap: () async {
              final family = await showDialog<String>(
                context: context,
                builder: (context) => FontFamilyDialog(
                  currentFamily: settings.fontFamily,
                ),
              );
              if (family != null) {
                ref.read(settingsProvider.notifier).setFontFamily(family);
              }
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Behavior'),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Haptic Feedback'),
            subtitle: const Text('Vibrate on key press'),
            value: settings.enableVibration,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setEnableVibration(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.brightness_high),
            title: const Text('Keep Screen On'),
            subtitle: const Text('Prevent screen from sleeping'),
            value: settings.keepScreenOn,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setKeepScreenOn(value);
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Notifications'),
          ListTile(
            leading: const Icon(Icons.notifications_active),
            title: const Text('Notification Rules'),
            subtitle: const Text('Configure pattern-based alerts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotificationRulesScreen(),
                ),
              );
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.dark_mode),
            title: const Text('Theme'),
            subtitle: Text(settings.darkMode ? 'Dark' : 'Light'),
            onTap: () async {
              final isDark = await showDialog<bool>(
                context: context,
                builder: (context) => ThemeDialog(
                  isDarkMode: settings.darkMode,
                ),
              );
              if (isDark != null) {
                ref.read(settingsProvider.notifier).setDarkMode(isDark);
              }
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Version'),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source Code'),
            subtitle: const Text('github.com/muxpod'),
            onTap: () async {
              final url = Uri.parse('https://github.com/muxpod');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
