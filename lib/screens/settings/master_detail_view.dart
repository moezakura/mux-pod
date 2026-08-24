import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import 'categories/settings_category_body.dart';
import 'categories/settings_category_list.dart';
import 'settings_category.dart';
import 'widgets/settings_app_bar_title.dart';

/// タブレット（>=600dp）のマスター / ディテール2ペイン。
///
/// 左ペイン280: カテゴリ一覧（検索フィールドは P2 で Column 上部に固定追加）。
/// タップで右ペインを切替（push は発生しない = 戻るボタン非表示）。
/// 右ペインは IndexedStack によりカテゴリ別のスクロール位置を保持する（D5/H5）。
class SettingsMasterDetailView extends ConsumerWidget {
  const SettingsMasterDetailView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(settingsCategoryProvider);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: SettingsAppBarTitle(text: l10n.settingsTitle)),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: SettingsCategoryList(
              onCategorySelected: (category) => ref
                  .read(settingsCategoryProvider.notifier)
                  .select(category),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: selected.index,
              children: [
                for (final category in SettingsCategory.values)
                  SettingsCategoryBody(category: category),
              ],
            ),
          ),
        ],
      ),
    );
  }
}