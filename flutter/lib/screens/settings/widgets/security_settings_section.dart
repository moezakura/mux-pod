import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_settings.dart';
import '../../../providers/settings_provider.dart';

/// セキュリティ設定セクション
class SecuritySettingsSection extends ConsumerWidget {
  const SecuritySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(securitySettingsProvider);
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
                Icon(Icons.security, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Security',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Biometric Unlock
          SwitchListTile(
            title: const Text('Biometric Unlock'),
            subtitle: const Text('Use fingerprint or face to unlock'),
            secondary: const Icon(Icons.fingerprint),
            value: security.biometricUnlock,
            onChanged: (value) async {
              // TODO: Verify biometric availability before enabling
              await notifier.setBiometricUnlock(value);
            },
          ),

          // Require Auth on Launch
          SwitchListTile(
            title: const Text('Require Auth on Launch'),
            subtitle: const Text('Authenticate when app starts'),
            value: security.requireAuthOnLaunch,
            onChanged: security.biometricUnlock
                ? (value) async {
                    await notifier.updateSecuritySettings(
                      security.copyWith(requireAuthOnLaunch: value),
                    );
                  }
                : null,
          ),

          // Require Auth on Resume
          SwitchListTile(
            title: const Text('Require Auth on Resume'),
            subtitle: const Text('Authenticate when returning from background'),
            value: security.requireAuthOnResume,
            onChanged: security.biometricUnlock
                ? (value) async {
                    await notifier.updateSecuritySettings(
                      security.copyWith(requireAuthOnResume: value),
                    );
                  }
                : null,
          ),

          // Auth Timeout
          ListTile(
            title: const Text('Auth Timeout'),
            subtitle: Text(_formatTimeout(security.authTimeout)),
            trailing: const Icon(Icons.chevron_right),
            enabled: security.biometricUnlock && security.requireAuthOnResume,
            onTap: security.biometricUnlock && security.requireAuthOnResume
                ? () => _showAuthTimeoutPicker(context, ref, security)
                : null,
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Clipboard Clear Timeout
          ListTile(
            title: const Text('Clipboard Auto-Clear'),
            subtitle: Text(
              security.clipboardClearTimeout == 0
                  ? 'Disabled'
                  : '${security.clipboardClearTimeout} seconds',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showClipboardTimeoutPicker(context, ref, security),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Allow Screen Capture
          SwitchListTile(
            title: const Text('Allow Screen Capture'),
            subtitle: const Text('Enable screenshots and screen recording'),
            value: security.allowScreenCapture,
            onChanged: (value) async {
              await notifier.updateSecuritySettings(
                security.copyWith(allowScreenCapture: value),
              );
            },
          ),

          // Allow Show Password
          SwitchListTile(
            title: const Text('Allow Show Password'),
            subtitle: const Text('Show password visibility toggle'),
            value: security.allowShowPassword,
            onChanged: (value) async {
              await notifier.updateSecuritySettings(
                security.copyWith(allowShowPassword: value),
              );
            },
          ),

          // Allow Show Private Key
          SwitchListTile(
            title: const Text('Allow Show Private Key'),
            subtitle: const Text('Allow viewing SSH private keys'),
            value: security.allowShowPrivateKey,
            onChanged: (value) async {
              await notifier.updateSecuritySettings(
                security.copyWith(allowShowPrivateKey: value),
              );
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatTimeout(int seconds) {
    if (seconds < 60) {
      return '$seconds seconds';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return '$minutes minute${minutes > 1 ? 's' : ''}';
    } else {
      final hours = seconds ~/ 3600;
      return '$hours hour${hours > 1 ? 's' : ''}';
    }
  }

  void _showAuthTimeoutPicker(BuildContext context, WidgetRef ref, SecuritySettings security) {
    final options = [
      (60, '1 minute'),
      (300, '5 minutes'),
      (600, '10 minutes'),
      (1800, '30 minutes'),
      (3600, '1 hour'),
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
                'Auth Timeout',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((opt) {
              final (seconds, label) = opt;
              return ListTile(
                title: Text(label),
                trailing: seconds == security.authTimeout
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref.read(appSettingsProvider.notifier).updateSecuritySettings(
                        security.copyWith(authTimeout: seconds),
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

  void _showClipboardTimeoutPicker(BuildContext context, WidgetRef ref, SecuritySettings security) {
    final options = [
      (0, 'Disabled'),
      (30, '30 seconds'),
      (60, '1 minute'),
      (120, '2 minutes'),
      (300, '5 minutes'),
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
                'Clipboard Auto-Clear',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((opt) {
              final (seconds, label) = opt;
              return ListTile(
                title: Text(label),
                trailing: seconds == security.clipboardClearTimeout
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref.read(appSettingsProvider.notifier).updateSecuritySettings(
                        security.copyWith(clipboardClearTimeout: seconds),
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
