import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/version_info.dart';
import '../../../utils/external_links.dart';
import '../licenses_screen.dart';
import '../search/settings_search_item.dart';
import '../settings_category.dart';

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
          onTap: () {
            // 🤝#5: 起動は util（launchExternalUri）の単一ソースへ最小委譲
            // （固定 URL の Uri.parse は従来どおり当該箇所に残す・M2）。
            launchExternalUri(
              Uri.parse('https://github.com/moezakura/mux-pod'),
            );
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

/// About セクションの検索 descriptor（全3項目・フラット）。
///
/// フラットのため groupLabel は null。バージョン番号は動的值のため
/// ヘイストックには含めない（現在値は subtitle が担う・DR-11）。
final List<SettingsSearchItem> aboutSearchDescriptors = [
  SettingsSearchItem(
    category: SettingsCategory.about,
    orderInCategory: 0,
    id: 'version',
    title: (l10n) => l10n.settingsVersion,
    icon: Icons.info,
  ),
  SettingsSearchItem(
    category: SettingsCategory.about,
    orderInCategory: 1,
    id: 'sourceCode',
    title: (l10n) => l10n.settingsSourceCode,
    icon: Icons.code,
  ),
  SettingsSearchItem(
    category: SettingsCategory.about,
    orderInCategory: 2,
    id: 'licenses',
    title: (l10n) => l10n.settingsLicenses,
    description: (l10n) => l10n.settingsLicensesDescription,
    icon: Icons.description,
  ),
];
