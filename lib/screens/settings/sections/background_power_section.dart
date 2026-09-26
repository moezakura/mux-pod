import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../search/settings_search_item.dart';
import '../settings_category.dart';
import '../widgets/settings_section_header.dart';

String networkLabel(AppLocalizations l10n, NetworkKind network) =>
    switch (network) {
      NetworkKind.mobile => l10n.settingsBackgroundMobile,
      NetworkKind.wifi => l10n.settingsBackgroundWifi,
      NetworkKind.unknown => l10n.settingsBackgroundUnknown,
    };

String modeLabel(AppLocalizations l10n, BackgroundMode mode) => switch (mode) {
  BackgroundMode.connection => l10n.settingsPowerConnection,
  BackgroundMode.balanced => l10n.settingsPowerBalanced,
  BackgroundMode.powerSaving => l10n.settingsPowerSaving,
};

String modeDescription(AppLocalizations l10n, BackgroundMode mode) =>
    switch (mode) {
      BackgroundMode.connection => l10n.settingsPowerConnectionDescription,
      BackgroundMode.balanced => l10n.settingsPowerBalancedDescription,
      BackgroundMode.powerSaving => l10n.settingsPowerSavingDescription,
    };

class BackgroundPowerSection extends ConsumerWidget {
  const BackgroundPowerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(title: l10n.settingsBackgroundPower),
        for (final network in NetworkKind.values)
          ListTile(
            key: ValueKey('background-${network.name}'),
            leading: Icon(
              network == NetworkKind.wifi
                  ? Icons.wifi
                  : network == NetworkKind.mobile
                  ? Icons.signal_cellular_alt
                  : Icons.help_outline,
            ),
            title: Text(networkLabel(l10n, network)),
            subtitle: Text(
              modeLabel(l10n, settings.backgroundModeFor(network)),
            ),
            onTap: () async {
              final selected = await showDialog<BackgroundMode>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: Text(networkLabel(l10n, network)),
                  children: [
                    for (final mode in BackgroundMode.values)
                      ListTile(
                        key: ValueKey('mode-${mode.name}'),
                        leading: Icon(
                          settings.backgroundModeFor(network) == mode
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(modeLabel(l10n, mode)),
                        subtitle: Text(modeDescription(l10n, mode)),
                        onTap: () => Navigator.pop(context, mode),
                      ),
                  ],
                ),
              );
              if (selected != null && context.mounted) {
                await ref
                    .read(settingsProvider.notifier)
                    .setBackgroundMode(network, selected);
              }
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.settingsBackgroundPowerNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

final backgroundPowerSearchDescriptors = [
  for (final network in NetworkKind.values)
    SettingsSearchItem(
      category: SettingsCategory.connection,
      orderInCategory: 13 + network.index,
      id: 'background-${network.name}',
      title: (l10n) => networkLabel(l10n, network),
      groupLabel: (l10n) => l10n.settingsBackgroundPower,
      description: (l10n) => l10n.settingsBackgroundPowerNote,
      valueLabels: [
        for (final mode in BackgroundMode.values)
          (l10n) => modeLabel(l10n, mode),
      ],
      icon: Icons.battery_saver,
    ),
];
