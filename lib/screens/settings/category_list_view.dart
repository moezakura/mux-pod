import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import 'categories/settings_category_list.dart';
import 'category_detail_screen.dart';
import 'widgets/settings_app_bar_title.dart';

/// スマホ（<600dp）のカテゴリ一覧画面。
///
/// 既存 _buildAppBar スタイル（floating/pinned/expandedHeight 100・Surface 0.95）を維持。
/// 検索フィールドは P2 で SliverPersistentHeader(pinned) として追加される。
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SettingsCategoryList(
                  onCategorySelected: (category) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsCategoryDetailScreen(category: category),
                      ),
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}