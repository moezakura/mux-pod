import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/version_info.dart';
import '../licenses_screen.dart';

/// About（このアプリについて）カテゴリ（フラット・グループ見出しなし）。
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.info),
          title: Text(l10n.settingsVersion),
          subtitle: Text(VersionInfo.version),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: Text(l10n.settingsSourceCode),
          subtitle: const Text('github.com/moezakura/mux-pod'),
          onTap: () async {
            final url = Uri.parse('https://github.com/moezakura/mux-pod');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.description),
          title: Text(l10n.settingsLicenses),
          subtitle: Text(l10n.settingsLicensesDescription),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LicensesScreen()),
            );
          },
        ),
      ],
    );
  }
}