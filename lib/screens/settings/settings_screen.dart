import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notification_rules_screen.dart';

/// 設定画面
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            subtitle: const Text('14'),
            onTap: () {
              // TODO: フォントサイズ変更ダイアログ
            },
          ),
          ListTile(
            leading: const Icon(Icons.font_download),
            title: const Text('Font Family'),
            subtitle: const Text('JetBrains Mono'),
            onTap: () {
              // TODO: フォント選択ダイアログ
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Behavior'),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Haptic Feedback'),
            subtitle: const Text('Vibrate on key press'),
            value: true,
            onChanged: (value) {
              // TODO: 設定を保存
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.brightness_high),
            title: const Text('Keep Screen On'),
            subtitle: const Text('Prevent screen from sleeping'),
            value: true,
            onChanged: (value) {
              // TODO: 設定を保存
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
            subtitle: const Text('Dark'),
            onTap: () {
              // TODO: テーマ選択ダイアログ
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
            onTap: () {
              // TODO: ブラウザでGitHubを開く
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
