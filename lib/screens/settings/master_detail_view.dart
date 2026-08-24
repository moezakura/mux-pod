import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import 'categories/settings_category_body.dart';
import 'categories/settings_category_list.dart';
import 'search/settings_search_item.dart';
import 'search/settings_search_provider.dart';
import 'search/settings_search_results_view.dart';
import 'settings_category.dart';
import 'widgets/settings_app_bar_title.dart';
import 'widgets/settings_search_field.dart';

/// タブレット（>=600dp）のマスター / ディテール2ペイン。
///
/// 左ペイン280: 検索フィールド（Column 上部に固定）+ カテゴリ一覧。
/// クエリ非空のときは左ペイン内の一覧を検索結果に置換し、右ペインは
/// 選択カテゴリの詳細のまま（§4.4）。タップで右ペインを切替
/// （push は発生しない = 戻るボタン非表示）。右ペインは IndexedStack に
/// よりカテゴリ別のスクロール位置を保持する。
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsSearchField(),
                Expanded(
                  child: _SearchContentSwitcher(
                    onResultTap: (context, item) {
                      // タブレット: カテゴリ選択 + クエリ clear（§4.4）
                      ref
                          .read(settingsCategoryProvider.notifier)
                          .select(item.category);
                      ref.read(settingsSearchProvider.notifier).clear();
                    },
                  ),
                ),
              ],
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

/// クエリ非空時は検索結果ビュー、空時はカテゴリ一覧を表示する切り替え。
class _SearchContentSwitcher extends ConsumerWidget {
  final void Function(BuildContext context, SettingsSearchItem item)
  onResultTap;

  const _SearchContentSwitcher({required this.onResultTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(settingsSearchProvider).trim();
    if (query.isNotEmpty) {
      return SettingsSearchResultsView(onResultTap: onResultTap);
    }
    return SettingsCategoryList(
      onCategorySelected: (category) =>
          ref.read(settingsCategoryProvider.notifier).select(category),
    );
  }
}
