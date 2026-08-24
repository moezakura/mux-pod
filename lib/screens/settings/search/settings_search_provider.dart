import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_lookup.dart';
import '../../../providers/settings_provider.dart';
import '../sections/about_section.dart';
import '../sections/behavior_section.dart';
import '../sections/connection_section.dart';
import '../sections/display_section.dart';
import '../settings_category.dart';
import 'settings_search_item.dart';

/// 検索インデックス。
///
/// 全36項目（Display 10 / Behavior 13 / Connection 10 / About 3）の descriptor と、
/// **en と ja の両ロケール**の [AppLocalizations] を固定的に保持する（M-2）。
/// `language` 値（'system'/'ja'/'en'）によらず、エン・ジャのラベル集合を
/// 常時並置するため、言語横断検索（en 表示中の「フォント」、ja 表示中の
/// "font" / "ssh"）が成立する。ヒット時の「現在ロケール優先」ランキングは
/// [SettingsSearchIndex.current] で判定する。
class SettingsSearchIndex {
  const SettingsSearchIndex({
    required this.items,
    required this.current,
    required this.other,
  });

  /// 全36項目の descriptor（カテゴリ順 = [SettingsCategory] enum 順に連結）。
  final List<SettingsSearchItem> items;

  /// 現在ロケールの [AppLocalizations]（'system' は端末ロケールで解決）。
  final AppLocalizations current;

  /// もう一方のロケール（en ⇄ ja）。
  final AppLocalizations other;
}

/// 検索インデックス Provider。
///
/// `settingsProvider.language` **のみ** watch する（M-5: トグルや値変更では
/// 再構築されない）。インデックスは言語切替時に1回だけ構築され、
/// 《キーストロークごとの l10n 再解決なし》を保証する。
final settingsSearchIndexProvider = Provider<SettingsSearchIndex>((ref) {
  final language = ref.watch(settingsProvider.select((s) => s.language));
  final ja = l10nForLanguage('ja');
  final en = l10nForLanguage('en');
  final isJa =
      language == 'ja' ||
      (language == 'system' &&
          PlatformDispatcher.instance.locale.languageCode == 'ja');
  return SettingsSearchIndex(
    items: [
      ...displaySearchDescriptors,
      ...behaviorSearchDescriptors,
      ...connectionSearchDescriptors,
      ...aboutSearchDescriptors,
    ],
    current: isJa ? ja : en,
    other: isJa ? en : ja,
  );
});

/// 検索クエリ Notifier（非 autoDispose → タブ切替・詳細 push を跨いで保持）。
///
/// connections の `ConnectionSearchNotifier` と同型（Pattern Map）。
class SettingsSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;

  void clear() => state = '';
}

final settingsSearchProvider = NotifierProvider<SettingsSearchNotifier, String>(
  SettingsSearchNotifier.new,
);

/// 検索ヒット（項目 + 現在ロケールでマッチしたか）。
class SettingsSearchHit {
  const SettingsSearchHit({
    required this.item,
    required this.matchedInCurrentLocale,
  });

  final SettingsSearchItem item;

  /// 現在ロケールのラベル集合でヒットしたか（ランキング第1キー・M-1）。
  final bool matchedInCurrentLocale;
}

/// フィルタ済み検索結果 Provider。
///
/// `query.trim().toLowerCase()` の contains で36項目を線形スキャンする（O(n)）。
/// ヘイストックは title / description / カテゴリ名 / グループ名 / 値ラベルの
/// en・ja 両解決。ランキング:
/// ①現在ロケールヒット優先 → ②カテゴリ順（enum 順）→ ③カテゴリ内 order。
/// 空クエリ・空白のみは空リスト（一覧表示を維持）。
final filteredSettingsProvider = Provider<List<SettingsSearchHit>>((ref) {
  final query = ref.watch(settingsSearchProvider).trim().toLowerCase();
  if (query.isEmpty) return const [];
  final index = ref.watch(settingsSearchIndexProvider);

  final hits = <SettingsSearchHit>[];
  for (final item in index.items) {
    final inCurrent = _matchesQuery(item, index.current, query);
    final inOther = _matchesQuery(item, index.other, query);
    if (inCurrent || inOther) {
      hits.add(
        SettingsSearchHit(item: item, matchedInCurrentLocale: inCurrent),
      );
    }
  }
  hits.sort((a, b) {
    if (a.matchedInCurrentLocale != b.matchedInCurrentLocale) {
      return a.matchedInCurrentLocale ? -1 : 1;
    }
    final cat = a.item.category.index.compareTo(b.item.category.index);
    if (cat != 0) return cat;
    return a.item.orderInCategory.compareTo(b.item.orderInCategory);
  });
  return hits;
});

/// [query]（lowercase）が [item] のいずれのラベル集合に contains されるか。
///
/// 対象: title / description / 所属カテゴリ名 / グループ名 / 値ラベル（§4.1）。
/// 動的な現在値（subtitle）は含めない（DR-11・critic H2）。
bool _matchesQuery(
  SettingsSearchItem item,
  AppLocalizations l10n,
  String query,
) {
  bool contains(String? text) =>
      text != null && text.toLowerCase().contains(query);
  if (contains(item.title(l10n))) return true;
  if (contains(item.description?.call(l10n))) return true;
  if (contains(item.category.labelKey(l10n))) return true;
  if (contains(item.groupLabel?.call(l10n))) return true;
  for (final label in item.valueLabels) {
    if (contains(label(l10n))) return true;
  }
  return false;
}
