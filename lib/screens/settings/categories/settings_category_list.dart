import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../settings_category.dart';

/// カテゴリ ListTile 一覧。
///
/// スマホ一覧（SettingsCategoryListView）とタブレット左ペイン
/// （SettingsMasterDetailView）で共用する。タップ先の挙動は
/// [onCategorySelected] で外部から注入する（push / Notifier select）。
/// settingsProvider は watch しない（D8/M2）。
class SettingsCategoryList extends StatelessWidget {
  final ValueChanged<SettingsCategory> onCategorySelected;

  const SettingsCategoryList({
    super.key,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // 4カテゴリのみのため Column で列挙する。スマホ一覧は CustomScrollView が
    // スクロールを担い、タブレット左ペインでは固有高さで収まる
    // （ListView を SliverList 内にネストすると unbounded になるため）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final category in SettingsCategory.values)
          ListTile(
            leading: Icon(category.icon),
            title: Text(category.labelKey(l10n)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onCategorySelected(category),
          ),
      ],
    );
  }
}