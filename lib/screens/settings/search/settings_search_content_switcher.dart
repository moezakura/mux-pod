import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../categories/settings_category_list.dart';
import '../settings_category.dart';
import 'settings_search_item.dart';
import 'settings_search_provider.dart';
import 'settings_search_results_view.dart';

/// クエリ非空時は検索結果ビュー、空時はカテゴリ一覧を表示する切り替え。
///
/// スマホ一覧（SliverToBoxAdapter）とタブレット左ペイン（Column 内）で
/// 共用する。タップ時の挙動はコールバックで外部から注入する:
/// - [onResultTap]: 検索結果タイルのタップ（スマホ=push / タブレット=select+clear）
/// - [onCategorySelected]: カテゴリ一覧リストのタップ（スマホ=push / タブレット=select）
class SettingsSearchContentSwitcher extends ConsumerWidget {
  final void Function(BuildContext context, SettingsSearchItem item)
  onResultTap;
  final ValueChanged<SettingsCategory> onCategorySelected;

  const SettingsSearchContentSwitcher({
    super.key,
    required this.onResultTap,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(settingsSearchProvider).trim();
    if (query.isNotEmpty) {
      return SettingsSearchResultsView(onResultTap: onResultTap);
    }
    return SettingsCategoryList(onCategorySelected: onCategorySelected);
  }
}
