import 'package:flutter/material.dart';

import '../../../screens/settings/search/settings_search_item.dart';
import '../../../screens/settings/settings_category.dart';
import '../update_source.dart';

/// Settings-search entries for the updater. Empty where the updater row is
/// hidden (non-Android), so search never points at a missing row.
List<SettingsSearchItem> updaterSearchDescriptors({required int order}) => [
  if (UpdateSource.isPlatformSupported)
    SettingsSearchItem(
      category: SettingsCategory.about,
      orderInCategory: order,
      id: 'softwareUpdate',
      title: (l10n) => l10n.updaterTitle,
      description: (l10n) => l10n.updaterCheckNow,
      icon: Icons.system_update,
    ),
];
