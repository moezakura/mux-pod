import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import 'category_detail_screen.dart';
import 'search/settings_search_content_switcher.dart';
import 'widgets/settings_search_field.dart';
import 'widgets/settings_app_bar_title.dart';

/// スマホ（<600dp）のカテゴリ一覧画面。
///
/// SliverAppBar（floating/pinned/expandedHeight 100・Surface 0.95）の直下に
/// 検索フィールドを SliverPersistentHeader(pinned) としてピン留めする（R-8）。
/// クエリ非空のときは一覧コンテンツを検索結果ビューに置換する。
class SettingsCategoryListView extends StatelessWidget {
  const SettingsCategoryListView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            expandedHeight: 100,
            backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
              title: SettingsAppBarTitle(text: l10n.settingsTitle),
            ),
          ),
          // 検索フィールド（ピン留め・クエリ空でも常設）
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchFieldHeaderDelegate(
              child: const SettingsSearchField(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
            sliver: SliverToBoxAdapter(
              child: SettingsSearchContentSwitcher(
                onResultTap: (context, item) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SettingsCategoryDetailScreen(category: item.category),
                    ),
                  );
                },
                onCategorySelected: (category) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SettingsCategoryDetailScreen(category: category),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 検索フィールドのピン留めヘッダデリゲート。
///
/// 高さは実測（TextField kMinInteractiveDimension 48 + padding 16 = 64）。
/// min/max を等しくしないと pinned ヘッダーの paintExtent と layoutExtent が
/// 食い違い SliverGeometry 検証に失敗するため、実高さに一致させる。
class _SearchFieldHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _SearchFieldHeaderDelegate({required this.child});

  @override
  double get minExtent => _kSearchHeaderHeight;

  @override
  double get maxExtent => _kSearchHeaderHeight;

  static const double _kSearchHeaderHeight = 64;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _SearchFieldHeaderDelegate oldDelegate) =>
      child != oldDelegate.child;
}
