import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../settings_category.dart';
import 'settings_search_item.dart';
import 'settings_search_provider.dart';
import '../widgets/settings_section_header.dart';

/// 検索結果ビュー。
///
/// クエリ非空のときに、一覧（カテゴリ ListTile）の代わりに表示する。
/// - カテゴリ別グループ: カテゴリ名見出し（Semantics heading は P3-C10 で付与）
///   の下に、ヒットした [SettingsSearchItem] の ListTile を表示
/// - タイル: タイトル = 項目名 / subtitle = 所属カテゴリ・グループ名 /
///   leading = 該当項目のアイコンの流用（DR-12・設計 §4.4）
/// - 空状態: settingsNoResults + settingsNoResultsHint + クリアボタン
/// - 結果タップ: スマホ = カテゴリ詳細へ push（クエリ保持）/
///   タブレット = カテゴリ選択 + クエリ clear（§L2-2）
class SettingsSearchResultsView extends ConsumerWidget {
  /// 結果タイルのタップ時コールバック。
  ///
  /// スマホ: カテゴリ詳細画面への push / タブレット: カテゴリ選択 +
  /// クエリ clear。クエリ保持の有無もコールバック側で制御する。
  final void Function(BuildContext context, SettingsSearchItem item)
  onResultTap;

  const SettingsSearchResultsView({super.key, required this.onResultTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hits = ref.watch(filteredSettingsProvider);
    if (hits.isEmpty) {
      return _EmptyResults(
        onClear: () => ref.read(settingsSearchProvider.notifier).clear(),
      );
    }

    // カテゴリ別にグループ化する（結果は filtered で既にカテゴリ順）。
    final grouped = <SettingsCategory, List<SettingsSearchHit>>{};
    for (final hit in hits) {
      grouped.putIfAbsent(hit.item.category, () => []).add(hit);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            l10n.settingsSearchResults,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final entry in grouped.entries) ...[
          // グループ見出し = カテゴリ名（Semantics heading は P3-C10）
          SettingsSectionHeader(title: entry.key.labelKey(l10n)),
          for (final hit in entry.value)
            ListTile(
              leading: Icon(
                hit.item.icon,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(hit.item.title(l10n)),
              subtitle: Text(
                hit.item.groupLabel?.call(l10n) ?? entry.key.labelKey(l10n),
              ),
              onTap: () => onResultTap(context, hit.item),
            ),
        ],
      ],
    );
  }
}

/// 空結果（クエリが存在するが一致なし）。
class _EmptyResults extends StatelessWidget {
  final VoidCallback onClear;

  const _EmptyResults({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsNoResults,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settingsNoResultsHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear, size: 16),
              label: Text(l10n.settingsClearSearch),
            ),
          ),
        ],
      ),
    );
  }
}
